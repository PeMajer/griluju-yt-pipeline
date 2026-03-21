namespace :channels do
  desc "Resolve YouTube channel_id from URL. Use URL=https://youtube.com/@Handle"
  task resolve_id: :environment do
    url = ENV["URL"]
    abort "Použití: rails channels:resolve_id URL=https://youtube.com/@Handle" if url.blank?

    stdout, stderr, status = Open3.capture3(
      "/opt/pyenv/bin/yt-dlp",
      "--print", "channel_id",
      "--skip-download",
      url
    )

    unless status.success?
      abort "yt-dlp selhalo: #{stderr.strip}"
    end

    channel_id = stdout.strip
    puts "channel_id: #{channel_id}"
    puts "RSS feed:   https://www.youtube.com/feeds/videos.xml?channel_id=#{channel_id}"
  end
end
