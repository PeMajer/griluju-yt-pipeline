class YoutubeVideo < ApplicationRecord
  belongs_to :youtube_channel
  has_one    :video_transcript, dependent: :destroy

  PROCESSING_STATUSES = %w[new metadata_fetched transcript_ready failed skipped].freeze

  validates :youtube_video_id, presence: true, uniqueness: true
  validates :processing_status, inclusion: { in: PROCESSING_STATUSES }

  # Scopy pro API dotazy
  scope :pending_webhook, -> { where(processing_status: "transcript_ready", webhook_sent_at: nil) }
  scope :queued_for_blog, -> { where(queued_for_blog: true) }

  # Predikáty pro idempotence guardy v jobech
  def new?              = processing_status == "new"
  def metadata_fetched? = processing_status == "metadata_fetched"
  def transcript_ready? = processing_status == "transcript_ready"
  def failed?           = processing_status == "failed"
  def skipped?          = processing_status == "skipped"

  def mark_failed!(reason)
    update!(processing_status: "failed", failed_reason: reason)
  end

  def mark_skipped!(reason)
    update!(processing_status: "skipped", failed_reason: reason)
  end
end
