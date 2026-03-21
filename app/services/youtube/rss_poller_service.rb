module Youtube
  class RssPollerService
    def self.call(channel)
      new(channel).call
    end

    def initialize(channel)
      @channel = channel
    end

    def call
      feed = Feedjira.parse(fetch_rss)
      feed.entries.each { |entry| process_entry(entry) }
    rescue StandardError => e
      Rails.logger.error "[RssPoller] Failed for #{@channel.channel_id}: #{e.message}"
      raise
    end

    private

    def fetch_rss
      HTTP.get(@channel.rss_url).to_s
    end

    def process_entry(entry)
      video_id = extract_video_id(entry)
      return if video_id.blank?

      video = YoutubeVideo.find_or_create_by!(youtube_video_id: video_id) do |v|
        v.youtube_channel   = @channel
        v.title             = entry.title
        v.video_url         = entry.url
        v.published_at      = entry.published&.utc
        v.processing_status = "new"
      end

      ProcessVideoJob.perform_later(video.id) if video.previously_new_record?
    rescue ActiveRecord::RecordNotUnique
      Rails.logger.info "[RssPoller] Race condition handled for #{video_id}"
    end

    def extract_video_id(entry)
      uri = URI.parse(entry.url.to_s)
      CGI.parse(uri.query.to_s)["v"]&.first
    rescue URI::InvalidURIError
      nil
    end
  end
end
