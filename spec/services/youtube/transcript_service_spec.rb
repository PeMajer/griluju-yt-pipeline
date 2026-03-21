require "rails_helper"

RSpec.describe Youtube::TranscriptService do
  let(:channel) { create(:youtube_channel, default_language: "en") }
  let(:video)   { create(:youtube_video, youtube_channel: channel, processing_status: "metadata_fetched") }

  subject(:service) { described_class.new(video) }

  # Pomocná metoda pro mock VTT souboru
  def stub_vtt_file(path, content)
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with(path).and_return(true)
    allow(File).to receive(:read).with(path).and_return(content)
    allow(Dir).to receive(:glob).and_call_original
    allow(Dir).to receive(:glob).with(a_string_including(video.youtube_video_id)).and_return([ path ])
  end

  SAMPLE_VTT = <<~VTT
    WEBVTT

    00:00:01.000 --> 00:00:04.000
    Today we smoke a brisket low

    00:00:03.000 --> 00:00:06.000
    low and slow for twelve hours
  VTT

  describe "#call" do
    context "když yt-dlp najde manuální titulky" do
      before do
        allow(Open3).to receive(:capture3).and_return([ "", "", instance_double(Process::Status, success?: true, exitstatus: 0) ])
        allow(FileUtils).to receive(:mkdir_p)
        allow(FileUtils).to receive(:rm_f)
        stub_vtt_file("/tmp/vtt/#{video.youtube_video_id}.en.vtt", SAMPLE_VTT)
        allow(NotifyBlogJob).to receive(:perform_later)
      end

      it "vytvoří VideoTranscript se source_type manual_subtitles" do
        service.call
        expect(video.reload.video_transcript.source_type).to eq("manual_subtitles")
      end

      it "nastaví processing_status na transcript_ready" do
        service.call
        expect(video.reload.processing_status).to eq("transcript_ready")
      end

      it "spustí NotifyBlogJob" do
        service.call
        expect(NotifyBlogJob).to have_received(:perform_later).with(video.id)
      end

      it "uloží language detekovaný z názvu souboru" do
        service.call
        expect(video.reload.video_transcript.language).to eq("en")
      end
    end

    context "když manuální titulky nejsou dostupné ale Whisper uspěje" do
      let(:audio_path) { "/tmp/whisper/#{video.youtube_video_id}.mp3" }
      let(:vtt_path)   { "/tmp/whisper/#{video.youtube_video_id}.vtt" }

      before do
        ok_status   = instance_double(Process::Status, success?: true, exitstatus: 0)
        fail_status = instance_double(Process::Status, success?: false, exitstatus: 1)

        # yt-dlp --write-subs selže (žádné manuální titulky)
        allow(Open3).to receive(:capture3).with(
          Youtube::TranscriptService::YT_DLP_PATH,
          "--skip-download", "--no-playlist",
          "-o", anything,
          "--write-subs", "--sub-format", "vtt", "--sub-lang", Youtube::TranscriptService::SUB_LANGS,
          video.video_url
        ).and_return([ "", "WARNING: no subtitles", fail_status ])

        # yt-dlp audio download uspěje
        allow(Open3).to receive(:capture3).with(
          Youtube::TranscriptService::YT_DLP_PATH,
          "--extract-audio", "--audio-format", "mp3",
          "--no-playlist", "-o", audio_path,
          video.video_url
        ).and_return([ "", "", ok_status ])

        # Whisper uspěje
        allow(Open3).to receive(:capture3).with(
          Youtube::TranscriptService::WHISPER_PATH,
          audio_path,
          "--model", "medium",
          "--model_dir", Youtube::TranscriptService::WHISPER_MODEL_DIR,
          "--language", "en",
          "--output_format", "vtt",
          "--output_dir", Youtube::TranscriptService::WHISPER_OUTPUT_DIR,
          "--initial_prompt", Youtube::TranscriptService::WHISPER_PROMPT
        ).and_return([ "", "", ok_status ])

        allow(FileUtils).to receive(:mkdir_p)
        allow(FileUtils).to receive(:rm_f)
        allow(Dir).to receive(:glob).and_return([])  # žádný VTT ze --write-subs

        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(audio_path).and_return(true)
        allow(File).to receive(:exist?).with(vtt_path).and_return(true)
        allow(File).to receive(:read).with(vtt_path).and_return(SAMPLE_VTT)

        allow(NotifyBlogJob).to receive(:perform_later)
      end

      it "vytvoří VideoTranscript se source_type whisper_local" do
        service.call
        expect(video.reload.video_transcript.source_type).to eq("whisper_local")
      end

      it "smaže audio soubor v ensure bloku" do
        service.call
        expect(FileUtils).to have_received(:rm_f).with(audio_path)
      end

      it "smaže Whisper VTT v ensure bloku" do
        service.call
        expect(FileUtils).to have_received(:rm_f).with(vtt_path)
      end
    end

    context "když selžou manuální titulky i Whisper, auto-captions uspějí" do
      before do
        fail_status = instance_double(Process::Status, success?: false, exitstatus: 1)
        ok_status   = instance_double(Process::Status, success?: true, exitstatus: 0)

        # --write-subs selže
        allow(Open3).to receive(:capture3).with(
          Youtube::TranscriptService::YT_DLP_PATH,
          "--skip-download", "--no-playlist",
          "-o", anything,
          "--write-subs", "--sub-format", "vtt", "--sub-lang", Youtube::TranscriptService::SUB_LANGS,
          video.video_url
        ).and_return([ "", "", fail_status ])

        # audio download selže (Whisper přeskočen)
        allow(Open3).to receive(:capture3).with(
          Youtube::TranscriptService::YT_DLP_PATH,
          "--extract-audio", "--audio-format", "mp3",
          "--no-playlist", "-o", anything,
          video.video_url
        ).and_return([ "", "", fail_status ])

        # --write-auto-subs uspěje
        allow(Open3).to receive(:capture3).with(
          Youtube::TranscriptService::YT_DLP_PATH,
          "--skip-download", "--no-playlist",
          "-o", anything,
          "--write-auto-subs", "--sub-format", "vtt", "--sub-lang", Youtube::TranscriptService::SUB_LANGS,
          video.video_url
        ).and_return([ "", "", ok_status ])

        allow(FileUtils).to receive(:mkdir_p)
        allow(FileUtils).to receive(:rm_f)

        auto_vtt = "/tmp/vtt/#{video.youtube_video_id}.en.vtt"
        # --write-subs selže před voláním glob (return nil), glob se volá jen jednou — pro auto-captions
        allow(Dir).to receive(:glob).and_return([ auto_vtt ])

        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(auto_vtt).and_return(true)
        allow(File).to receive(:read).with(auto_vtt).and_return(SAMPLE_VTT)
        allow(NotifyBlogJob).to receive(:perform_later)
      end

      it "vytvoří VideoTranscript se source_type auto_captions_youtube" do
        service.call
        expect(video.reload.video_transcript.source_type).to eq("auto_captions_youtube")
      end
    end

    context "když selžou všechny zdroje" do
      before do
        fail_status = instance_double(Process::Status, success?: false, exitstatus: 1)
        allow(Open3).to receive(:capture3).and_return([ "", "", fail_status ])
        allow(FileUtils).to receive(:mkdir_p)
        allow(FileUtils).to receive(:rm_f)
        allow(Dir).to receive(:glob).and_return([])
        allow(File).to receive(:exist?).and_return(false)
      end

      it "nastaví processing_status na failed" do
        service.call
        expect(video.reload.processing_status).to eq("failed")
      end

      it "uloží failed_reason no_transcript" do
        service.call
        expect(video.reload.failed_reason).to eq("no_transcript")
      end

      it "nespustí NotifyBlogJob" do
        allow(NotifyBlogJob).to receive(:perform_later)
        service.call
        expect(NotifyBlogJob).not_to have_received(:perform_later)
      end
    end
  end

  describe "#detect_language (přes build_transcript)" do
    it "detekuje jazyk z názvu VTT souboru" do
      vtt_path = "/tmp/vtt/#{video.youtube_video_id}.fr.vtt"
      allow(File).to receive(:read).with(vtt_path).and_return(SAMPLE_VTT)

      transcript = service.send(:build_transcript, vtt_path, source_type: "manual_subtitles")
      expect(transcript.language).to eq("fr")
    end

    it "použije default_language kanálu jako fallback" do
      vtt_path = "/tmp/vtt/#{video.youtube_video_id}.vtt"  # bez lang v názvu
      allow(File).to receive(:read).with(vtt_path).and_return(SAMPLE_VTT)

      transcript = service.send(:build_transcript, vtt_path, source_type: "manual_subtitles")
      expect(transcript.language).to eq("en")  # z factory channel.default_language
    end
  end

  describe "quality_score a word_count (via VideoTranscript callbacks)" do
    before do
      allow(Open3).to receive(:capture3).and_return([ "", "", instance_double(Process::Status, success?: true, exitstatus: 0) ])
      allow(FileUtils).to receive(:mkdir_p)
      allow(FileUtils).to receive(:rm_f)
      stub_vtt_file("/tmp/vtt/#{video.youtube_video_id}.en.vtt", SAMPLE_VTT)
      allow(NotifyBlogJob).to receive(:perform_later)
    end

    it "nastaví transcript_quality_score 3 pro manual_subtitles" do
      service.call
      expect(video.reload.video_transcript.transcript_quality_score).to eq(3)
    end

    it "nastaví word_count podle cleaned_transcript" do
      service.call
      transcript = video.reload.video_transcript
      expected = transcript.cleaned_transcript.split.size
      expect(transcript.word_count).to eq(expected)
    end
  end
end
