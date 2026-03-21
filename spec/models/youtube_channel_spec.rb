require "rails_helper"

RSpec.describe YoutubeChannel, type: :model do
  describe "validations" do
    subject { create(:youtube_channel) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:channel_id) }
    it { is_expected.to validate_uniqueness_of(:channel_id) }
    it { is_expected.to validate_numericality_of(:backfill_limit).is_greater_than(0).is_less_than_or_equal_to(200) }
  end

  describe "associations" do
    it { is_expected.to have_many(:youtube_videos).dependent(:destroy) }
  end

  describe "scopes" do
    it "active returns only active channels" do
      active   = create(:youtube_channel, active: true)
      inactive = create(:youtube_channel, active: false)

      expect(YoutubeChannel.active).to include(active)
      expect(YoutubeChannel.active).not_to include(inactive)
    end
  end

  describe "#rss_url" do
    it "returns correct YouTube RSS feed URL" do
      channel = build(:youtube_channel, channel_id: "UCxxxxxxxxxxxxxxxxxxx1")
      expect(channel.rss_url).to eq(
        "https://www.youtube.com/feeds/videos.xml?channel_id=UCxxxxxxxxxxxxxxxxxxx1"
      )
    end
  end
end
