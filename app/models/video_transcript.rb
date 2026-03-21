class VideoTranscript < ApplicationRecord
  belongs_to :youtube_video

  SOURCE_TYPES = %w[manual_subtitles whisper_local auto_captions_youtube].freeze

  QUALITY_SCORES = {
    "manual_subtitles"      => 3,
    "whisper_local"         => 2,
    "auto_captions_youtube" => 1
  }.freeze

  validates :source_type, inclusion: { in: SOURCE_TYPES }, allow_nil: true

  before_save :set_quality_score
  before_save :set_word_count

  private

  def set_quality_score
    self.transcript_quality_score = QUALITY_SCORES.fetch(source_type.to_s, 0)
  end

  def set_word_count
    self.word_count = cleaned_transcript&.split&.size || 0
  end
end
