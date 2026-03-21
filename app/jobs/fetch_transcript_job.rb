class FetchTranscriptJob < ApplicationJob
  queue_as :yt_dlp

  sidekiq_options retry: 3
  sidekiq_retry_in do |count, _exception|
    case count
    when 0 then  5 * 60   # 5 minut
    when 1 then 15 * 60   # 15 minut
    else        45 * 60   # 45 minut
    end
  end

  def perform(video_id)
    video = YoutubeVideo.find(video_id)

    # Idempotence guard
    return if video.transcript_ready? || video.skipped?

    Youtube::TranscriptService.call(video)
  rescue StandardError => e
    video&.increment!(:retry_count)
    Rails.logger.error "[Pipeline] FetchTranscriptJob failed for #{video_id}: #{e.message}"
    raise
  end
end
