class ProcessVideoJob < ApplicationJob
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

    metadata = Youtube::VideoMetadataService.call(video)

    if (reason = skip_reason_for(metadata))
      video.mark_skipped!(reason)
      Rails.logger.info "[Pipeline] Skipped #{video.youtube_video_id}: #{reason}"
      return
    end

    video.update!(
      title:             metadata["title"],
      description:       metadata["description"],
      thumbnail_url:     metadata["thumbnail"],
      duration_seconds:  metadata["duration"],
      processing_status: "metadata_fetched"
    )

    FetchTranscriptJob.perform_later(video.id)
  rescue StandardError => e
    video&.increment!(:retry_count)
    Rails.logger.error "[Pipeline] ProcessVideoJob failed for #{video_id}: #{e.message}"
    raise
  end

  private

  def skip_reason_for(metadata)
    return "live_content" unless metadata["live_status"] == "not_live"
    return "short_video" if metadata["webpage_url"].to_s.include?("/shorts/")
    return "short_video" if metadata["duration"].to_i < 120
    nil
  end
end
