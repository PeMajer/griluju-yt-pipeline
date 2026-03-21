class NotifyBlogJob < ApplicationJob
  queue_as :critical

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
    Blog::WebhookService.call(video)
    video.update!(webhook_sent_at: Time.current)
    Rails.logger.info "[Pipeline] Blog notified for #{video.youtube_video_id}"
  rescue StandardError => e
    Rails.logger.error "[Pipeline] NotifyBlogJob failed for #{video_id}: #{e.message}"
    raise
  end
end
