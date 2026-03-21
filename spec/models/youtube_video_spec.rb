require "rails_helper"

RSpec.describe YoutubeVideo, type: :model do
  describe "validations" do
    subject { create(:youtube_video) }

    it { is_expected.to validate_presence_of(:youtube_video_id) }
    it { is_expected.to validate_uniqueness_of(:youtube_video_id) }
    it { is_expected.to validate_inclusion_of(:processing_status).in_array(YoutubeVideo::PROCESSING_STATUSES) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:youtube_channel) }
    it { is_expected.to have_one(:video_transcript).dependent(:destroy) }
  end

  describe "status predikáty" do
    %w[new metadata_fetched transcript_ready failed skipped].each do |status|
      it "#{status}? vrátí true pro status=#{status}" do
        video = build(:youtube_video, processing_status: status)
        expect(video.public_send(:"#{status}?")).to be true
      end
    end
  end

  describe "#mark_failed!" do
    it "nastaví status a důvod" do
      video = create(:youtube_video)
      video.mark_failed!("yt-dlp error")
      expect(video.reload.processing_status).to eq("failed")
      expect(video.failed_reason).to eq("yt-dlp error")
    end
  end

  describe "#mark_skipped!" do
    it "nastaví status a důvod" do
      video = create(:youtube_video)
      video.mark_skipped!("short_video")
      expect(video.reload.processing_status).to eq("skipped")
      expect(video.failed_reason).to eq("short_video")
    end
  end
end
