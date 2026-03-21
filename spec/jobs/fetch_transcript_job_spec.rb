require "rails_helper"

RSpec.describe FetchTranscriptJob do
  let(:channel) { create(:youtube_channel) }
  let(:video)   { create(:youtube_video, youtube_channel: channel, processing_status: "metadata_fetched") }

  subject(:job) { described_class.new }

  describe "#perform" do
    context "normální průběh" do
      before do
        allow(Youtube::TranscriptService).to receive(:call)
      end

      it "volá TranscriptService" do
        job.perform(video.id)
        expect(Youtube::TranscriptService).to have_received(:call).with(video)
      end
    end

    context "idempotence — video je transcript_ready" do
      let(:video) { create(:youtube_video, :transcript_ready, youtube_channel: channel) }

      it "nevolá TranscriptService" do
        allow(Youtube::TranscriptService).to receive(:call)
        job.perform(video.id)
        expect(Youtube::TranscriptService).not_to have_received(:call)
      end
    end

    context "idempotence — video je skipped" do
      let(:video) { create(:youtube_video, :skipped, youtube_channel: channel) }

      it "nevolá TranscriptService" do
        allow(Youtube::TranscriptService).to receive(:call)
        job.perform(video.id)
        expect(Youtube::TranscriptService).not_to have_received(:call)
      end
    end

    context "TranscriptService selže" do
      before do
        allow(Youtube::TranscriptService).to receive(:call).and_raise(StandardError, "whisper OOM")
      end

      it "inkrementuje retry_count" do
        expect { job.perform(video.id) }.to raise_error(StandardError)
        expect(video.reload.retry_count).to eq(1)
      end

      it "propaguje chybu pro Sidekiq retry" do
        expect { job.perform(video.id) }.to raise_error(StandardError, "whisper OOM")
      end
    end
  end
end
