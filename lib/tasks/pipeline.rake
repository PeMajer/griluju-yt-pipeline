namespace :pipeline do
  desc "Re-queue failed videos for reprocessing. Use CHANNEL=UC... to filter by channel."
  task retry_failed: :environment do
    scope = YoutubeVideo.where(processing_status: "failed")

    if ENV["CHANNEL"].present?
      scope = scope.joins(:youtube_channel)
                   .where(youtube_channels: { channel_id: ENV["CHANNEL"] })
    end

    count = scope.count
    abort "Žádná failed videa nenalezena." if count.zero?

    puts "Re-queueing #{count} failed videí..."
    scope.find_each do |video|
      video.update!(processing_status: "new", failed_reason: nil, retry_count: 0)
      ProcessVideoJob.perform_later(video.id)
      puts "  ↻ #{video.youtube_video_id} — #{video.title}"
    end
    puts "Hotovo."
  end
end
