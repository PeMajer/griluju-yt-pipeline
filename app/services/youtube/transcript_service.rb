module Youtube
  class TranscriptService
    YT_DLP_PATH       = "/opt/pyenv/bin/yt-dlp".freeze
    WHISPER_PATH      = "/opt/pyenv/bin/whisper-ctranslate2".freeze
    WHISPER_MODEL     = "medium".freeze
    WHISPER_MODEL_DIR = ENV.fetch("WHISPER_MODEL_PATH", "/opt/whisper_models").freeze
    WHISPER_OUTPUT_DIR = "/tmp/whisper/".freeze

    # Doménový prompt pro lepší přesnost Whisper na BBQ terminologii
    WHISPER_PROMPT = "BBQ, brisket, bark, stall, tallow injection, spritzing, smoke ring, " \
                     "Traeger, Kamado Joe, Weber, Big Green Egg, offset smoker, pellet grill, " \
                     "pulled pork, pork butt, St. Louis ribs, spare ribs, baby back, " \
                     "dry rub, wet rub, marinade, brine, mop sauce, burnt ends, " \
                     "Aaron Franklin, Malcom Reed, Mad Scientist BBQ, Chud's BBQ".freeze

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
      # TODO: implementovat
      # yt-dlp --write-subs --sub-lang "en,en-US,en-GB" --skip-download --sub-format vtt
      # Vrátí VideoTranscript nebo nil
      nil
    end

    def fetch_with_whisper
      # TODO: implementovat
      # 1. Stáhnout audio: yt-dlp --extract-audio --audio-format mp3 -o /tmp/whisper/VIDEO_ID.%(ext)s URL
      # 2. Spustit whisper: whisper-ctranslate2 --model medium --model_dir WHISPER_MODEL_DIR ...
      # DŮLEŽITÉ: ensure blok pro cleanup audio + VTT souborů
      # DŮLEŽITÉ: fronta :whisper má limit 1 worker (OOM prevence)
      nil
    end

    def fetch_auto_captions
      # TODO: implementovat
      # yt-dlp --write-auto-subs --sub-lang "en,en-US" --skip-download --sub-format vtt
      # Poslední záchrana — nižší qualita než manual nebo whisper
      nil
    end
  end
end
