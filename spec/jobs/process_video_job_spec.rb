require "rails_helper"

RSpec.describe ProcessVideoJob do
  let(:channel) { create(:youtube_channel) }
  let(:video)   { create(:youtube_video, youtube_channel: channel, processing_status: "new") }

  subject(:job) { described_class.new }

  FULL_METADATA = {
    "title"       => "Brisket 12 Hours Low and Slow",
    "description" => "Competition brisket technique",
    "thumbnail"   => "https://i.ytimg.com/vi/abc123/hq720.jpg",
    "duration"    => 7200,
    "live_status" => "not_live",
    "webpage_url" => "https://www.youtube.com/watch?v=abc123"
  }.freeze

  before do
    allow(FetchTranscriptJob).to receive(:perform_later)
  end

  describe "#perform" do
    context "normální video" do
      before do
        allow(Youtube::VideoMetadataService).to receive(:call).and_return(FULL_METADATA)
      end

      it "uloží metadata na video" do
        job.perform(video.id)
        video.reload
        expect(video.title).to eq("Brisket 12 Hours Low and Slow")
        expect(video.thumbnail_url).to eq("https://i.ytimg.com/vi/abc123/hq720.jpg")
        expect(video.duration_seconds).to eq(7200)
      end

      it "nastaví processing_status na metadata_fetched" do
        job.perform(video.id)
        expect(video.reload.processing_status).to eq("metadata_fetched")
      end

      it "enqueue-uje FetchTranscriptJob" do
        job.perform(video.id)
        expect(FetchTranscriptJob).to have_received(:perform_later).with(video.id)
      end
    end

    context "idempotence — video je transcript_ready" do
      let(:video) { create(:youtube_video, :transcript_ready, youtube_channel: channel) }

      it "nevolá VideoMetadataService" do
        allow(Youtube::VideoMetadataService).to receive(:call)
        job.perform(video.id)
        expect(Youtube::VideoMetadataService).not_to have_received(:call)
      end
    end

    context "idempotence — video je skipped" do
      let(:video) { create(:youtube_video, :skipped, youtube_channel: channel) }

      it "nevolá VideoMetadataService" do
        allow(Youtube::VideoMetadataService).to receive(:call)
        job.perform(video.id)
        expect(Youtube::VideoMetadataService).not_to have_received(:call)
      end
    end

    context "live video" do
      before do
        allow(Youtube::VideoMetadataService).to receive(:call).and_return(
          FULL_METADATA.merge("live_status" => "is_live")
        )
      end

      it "označí video jako skipped s důvodem live_content" do
        job.perform(video.id)
        video.reload
        expect(video.processing_status).to eq("skipped")
        expect(video.failed_reason).to eq("live_content")
      end

      it "nespustí FetchTranscriptJob" do
        job.perform(video.id)
        expect(FetchTranscriptJob).not_to have_received(:perform_later)
      end
    end

    context "YouTube Short (URL obsahuje /shorts/)" do
      before do
        allow(Youtube::VideoMetadataService).to receive(:call).and_return(
          FULL_METADATA.merge("webpage_url" => "https://www.youtube.com/shorts/abc123")
        )
      end

      it "označí video jako skipped s důvodem short_video" do
        job.perform(video.id)
        expect(video.reload.failed_reason).to eq("short_video")
      end
    end

    context "video kratší než 2 minuty" do
      before do
        allow(Youtube::VideoMetadataService).to receive(:call).and_return(
          FULL_METADATA.merge("duration" => 90)
        )
      end

      it "označí video jako skipped s důvodem short_video" do
        job.perform(video.id)
        expect(video.reload.failed_reason).to eq("short_video")
      end
    end

    context "VideoMetadataService selže" do
      before do
        allow(Youtube::VideoMetadataService).to receive(:call).and_raise(RuntimeError, "yt-dlp failed")
      end

      it "inkrementuje retry_count" do
        expect { job.perform(video.id) }.to raise_error(RuntimeError)
        expect(video.reload.retry_count).to eq(1)
      end

      it "propaguje chybu pro Sidekiq retry" do
        expect { job.perform(video.id) }.to raise_error(RuntimeError, "yt-dlp failed")
      end
    end
  end
end
