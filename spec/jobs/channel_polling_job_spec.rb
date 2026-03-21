require "rails_helper"

RSpec.describe ChannelPollingJob do
  let!(:active_channel)   { create(:youtube_channel, active: true) }
  let!(:inactive_channel) { create(:youtube_channel, active: false) }

  subject(:job) { described_class.new }

  before do
    allow(Youtube::RssPollerService).to receive(:call)
    allow(ProcessVideoJob).to receive(:perform_later)
    allow(FetchTranscriptJob).to receive(:perform_later)
  end

  describe "#perform" do
    it "polluje všechny aktivní kanály přes RssPollerService" do
      job.perform
      expect(Youtube::RssPollerService).to have_received(:call).with(active_channel)
    end

    it "nepolluje neaktivní kanály" do
      job.perform
      expect(Youtube::RssPollerService).not_to have_received(:call).with(inactive_channel)
    end

    it "aktualizuje last_checked_at na každém aktivním kanálu" do
      freeze_time do
        job.perform
        expect(active_channel.reload.last_checked_at).to be_within(1.second).of(Time.current)
      end
    end

    context "recovery — video stuck v metadata_fetched déle než 30 minut" do
      let!(:stuck_video) do
        create(:youtube_video,
               youtube_channel: active_channel,
               processing_status: "metadata_fetched",
               updated_at: 31.minutes.ago)
      end

      it "re-enqueue-uje FetchTranscriptJob pro stuck video" do
        job.perform
        expect(FetchTranscriptJob).to have_received(:perform_later).with(stuck_video.id)
      end

      it "neobnovuje čerstvé metadata_fetched video" do
        fresh_video = create(:youtube_video,
                             youtube_channel: active_channel,
                             processing_status: "metadata_fetched",
                             updated_at: 5.minutes.ago)
        job.perform
        expect(FetchTranscriptJob).not_to have_received(:perform_later).with(fresh_video.id)
      end
    end

    context "recovery — video stuck v new déle než 60 minut" do
      let!(:stuck_new_video) do
        create(:youtube_video,
               youtube_channel: active_channel,
               processing_status: "new",
               updated_at: 61.minutes.ago)
      end

      it "re-enqueue-uje ProcessVideoJob pro stuck video" do
        job.perform
        expect(ProcessVideoJob).to have_received(:perform_later).with(stuck_new_video.id)
      end

      it "neobnovuje čerstvé new video" do
        fresh_new = create(:youtube_video,
                           youtube_channel: active_channel,
                           processing_status: "new",
                           updated_at: 10.minutes.ago)
        job.perform
        expect(ProcessVideoJob).not_to have_received(:perform_later).with(fresh_new.id)
      end
    end

    context "recovery — stuck video patří neaktivnímu kanálu" do
      let!(:stuck_video_inactive) do
        create(:youtube_video,
               youtube_channel: inactive_channel,
               processing_status: "metadata_fetched",
               updated_at: 35.minutes.ago)
      end

      it "neobnoví stuck video z neaktivního kanálu" do
        job.perform
        expect(FetchTranscriptJob).not_to have_received(:perform_later).with(stuck_video_inactive.id)
      end
    end
  end
end
