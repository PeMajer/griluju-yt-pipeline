class YoutubeChannel < ApplicationRecord
  has_many :youtube_videos, dependent: :destroy

  validates :name,       presence: true
  validates :channel_id, presence: true, uniqueness: true
  validates :backfill_limit, numericality: { greater_than: 0, less_than_or_equal_to: 200 }

  scope :active, -> { where(active: true) }

  def rss_url
    "https://www.youtube.com/feeds/videos.xml?channel_id=#{channel_id}"
  end
end
