module Youtube
  class TranscriptService
    YT_DLP_PATH        = "/opt/pyenv/bin/yt-dlp".freeze
    WHISPER_PATH       = "/opt/pyenv/bin/whisper-ctranslate2".freeze
    WHISPER_MODEL      = "medium".freeze
    WHISPER_MODEL_DIR  = ENV.fetch("WHISPER_MODEL_PATH", "/opt/whisper_models").freeze
    WHISPER_OUTPUT_DIR = "/tmp/whisper/".freeze
    VTT_OUTPUT_DIR     = "/tmp/vtt/".freeze

    SUB_LANGS = "en,en-US,en-GB".freeze

    # Doménový prompt pro lepší přesnost Whisper na BBQ terminologii
    WHISPER_PROMPT = "BBQ, brisket, bark, stall, tallow injection, spritzing, smoke ring, " \
                     "Traeger, Kamado Joe, Weber, Big Green Egg, offset smoker, pellet grill, " \
                     "pulled pork, pork butt, pork shoulder, St. Louis ribs, spare ribs, baby back, " \
                     "dry rub, wet rub, marinade, brine, mop sauce, burnt ends, flat, point, " \
                     "internal temperature, probe tender, thermometer, Thermapen, Meater, " \
                     "Aaron Franklin, Malcom Reed, Mad Scientist BBQ, Chud's BBQ, kosher salt, coarse pepper".freeze

    def self.call(video)
      new(video).call
    end

    def initialize(video)
      @video = video
    end

    def call
      transcript = fetch_manual_subtitles || fetch_with_whisper || fetch_auto_captions

      if transcript
        @video.update!(processing_status: "transcript_ready")
        NotifyBlogJob.perform_later(@video.id)
      else
        @video.mark_failed!("no_transcript")
      end
    end

    private

    def fetch_manual_subtitles
      Rails.logger.info "[TranscriptService] Fetching manual subtitles for #{@video.youtube_video_id}"
      vtt_path = nil

      begin
        vtt_path = download_vtt(
          @video,
          flags: [ "--write-subs", "--sub-format", "vtt", "--sub-lang", SUB_LANGS ]
        )
        return nil unless vtt_path

        build_transcript(vtt_path, source_type: "manual_subtitles")
      ensure
        FileUtils.rm_f(vtt_path) if vtt_path && File.exist?(vtt_path)
      end
    end

    def fetch_with_whisper
      Rails.logger.info "[TranscriptService] Fetching with Whisper for #{@video.youtube_video_id}"
      audio_path  = nil
      whisper_vtt = nil

      begin
        audio_path  = download_audio(@video)
        return nil unless audio_path

        whisper_vtt = run_whisper(audio_path)
        return nil unless whisper_vtt

        build_transcript(whisper_vtt, source_type: "whisper_local")
      ensure
        FileUtils.rm_f(audio_path)  if audio_path  && File.exist?(audio_path)
        FileUtils.rm_f(whisper_vtt) if whisper_vtt && File.exist?(whisper_vtt)
      end
    end

    def fetch_auto_captions
      Rails.logger.info "[TranscriptService] Fetching auto-captions for #{@video.youtube_video_id}"
      vtt_path = nil

      begin
        vtt_path = download_vtt(
          @video,
          flags: [ "--write-auto-subs", "--sub-format", "vtt", "--sub-lang", SUB_LANGS ]
        )
        return nil unless vtt_path

        build_transcript(vtt_path, source_type: "auto_captions_youtube")
      ensure
        FileUtils.rm_f(vtt_path) if vtt_path && File.exist?(vtt_path)
      end
    end

    # Vrátí cestu k VTT souboru nebo nil pokud yt-dlp titulky nenašel
    def download_vtt(video, flags:)
      FileUtils.mkdir_p(VTT_OUTPUT_DIR)

      args = [
        YT_DLP_PATH,
        "--skip-download",
        "--no-playlist",
        "-o", File.join(VTT_OUTPUT_DIR, "#{video.youtube_video_id}.%(ext)s"),
        *flags,
        video.video_url
      ]

      stdout, stderr, status = Open3.capture3(*args)
      Rails.logger.debug "[TranscriptService] yt-dlp stdout: #{stdout}" if stdout.present?
      Rails.logger.debug "[TranscriptService] yt-dlp stderr: #{stderr}" if stderr.present?

      unless status.success?
        Rails.logger.warn "[TranscriptService] yt-dlp failed (#{status.exitstatus}): #{stderr.strip}"
        return nil
      end

      # yt-dlp zapisuje soubor jako VIDEO_ID.LANG.vtt — najdeme první shodu
      pattern = File.join(VTT_OUTPUT_DIR, "#{video.youtube_video_id}.*.vtt")
      Dir.glob(pattern).first
    end

    # Stáhne audio jako MP3, vrátí cestu k souboru nebo nil
    def download_audio(video)
      FileUtils.mkdir_p(WHISPER_OUTPUT_DIR)
      audio_path = File.join(WHISPER_OUTPUT_DIR, "#{video.youtube_video_id}.mp3")

      args = [
        YT_DLP_PATH,
        "--extract-audio",
        "--audio-format", "mp3",
        "--no-playlist",
        "-o", audio_path,
        video.video_url
      ]

      _, stderr, status = Open3.capture3(*args)

      unless status.success?
        Rails.logger.warn "[TranscriptService] yt-dlp audio download failed: #{stderr.strip}"
        return nil
      end

      File.exist?(audio_path) ? audio_path : nil
    end

    # Spustí whisper-ctranslate2, vrátí cestu k VTT výstupu nebo nil
    def run_whisper(audio_path)
      language = @video.youtube_channel&.default_language || "en"

      args = [
        WHISPER_PATH,
        audio_path,
        "--model", WHISPER_MODEL,
        "--model_dir", WHISPER_MODEL_DIR,
        "--language", language,
        "--output_format", "vtt",
        "--output_dir", WHISPER_OUTPUT_DIR,
        "--initial_prompt", WHISPER_PROMPT
      ]

      _, stderr, status = Open3.capture3(*args)

      unless status.success?
        Rails.logger.warn "[TranscriptService] Whisper failed: #{stderr.strip}"
        return nil
      end

      # whisper-ctranslate2 zapisuje BASENAME.vtt (bez cesty)
      basename = File.basename(audio_path, ".*")
      vtt_path = File.join(WHISPER_OUTPUT_DIR, "#{basename}.vtt")
      File.exist?(vtt_path) ? vtt_path : nil
    end

    # Přečte VTT soubor, vyčistí ho přes VttCleanerService a uloží VideoTranscript
    def build_transcript(vtt_path, source_type:)
      raw_vtt           = File.read(vtt_path)
      cleaned           = Blog::VttCleanerService.call(raw_vtt)

      return nil if cleaned.blank?

      @video.video_transcript&.destroy
      @video.create_video_transcript!(
        source_type:        source_type,
        raw_transcript:     raw_vtt,
        cleaned_transcript: cleaned,
        language:           detect_language(vtt_path),
        available:          true
      )
    end

    # Detekce jazyka z názvu VTT souboru (yt-dlp pojmenovává VIDEO_ID.LANG.vtt)
    # Fallback: default_language kanálu
    def detect_language(vtt_path)
      # Příklad: abc123.en.vtt → "en"
      match = File.basename(vtt_path).match(/\.([a-z]{2,3})\.vtt$/)
      match ? match[1] : (@video.youtube_channel&.default_language || "en")
    end
  end
end
