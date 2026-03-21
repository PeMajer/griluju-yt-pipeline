class ChannelPollingJob < ApplicationJob
  queue_as :default

  def perform
    recover_stuck_videos
    YoutubeChannel.active.find_each do |channel|
      Youtube::RssPollerService.call(channel)
      channel.update!(last_checked_at: Time.current)
    end
  end

  private

  def recover_stuck_videos
    # metadata_fetched déle než 30 min → FetchTranscriptJob se nikdy nespustil
    YoutubeVideo.where(processing_status: "metadata_fetched")
                .where("youtube_videos.updated_at < ?", 30.minutes.ago)
                .joins(:youtube_channel)
                .where(youtube_channels: { active: true })
                .find_each do |video|
      Rails.logger.warn "[Recovery] Re-enqueueing stuck video #{video.youtube_video_id}"
      FetchTranscriptJob.perform_later(video.id)
    end

    # new déle než 60 min → ProcessVideoJob se nikdy nespustil
    YoutubeVideo.where(processing_status: "new")
                .where("youtube_videos.updated_at < ?", 60.minutes.ago)
                .joins(:youtube_channel)
                .where(youtube_channels: { active: true })
                .find_each do |video|
      Rails.logger.warn "[Recovery] Re-enqueueing stuck new video #{video.youtube_video_id}"
      ProcessVideoJob.perform_later(video.id)
    end
  end
end
