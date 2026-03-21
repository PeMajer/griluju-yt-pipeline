module Blog
  class WebhookService
    def self.call(video)
      new(video).call
    end

    def initialize(video)
      @video = video
    end

    def call
      payload_json = build_payload.to_json
      signature    = OpenSSL::HMAC.hexdigest("SHA256", webhook_secret, payload_json)

      response = HTTP.headers(
        "Content-Type"    => "application/json",
        "X-Api-Key"       => ENV.fetch("BLOG_API_KEY"),
        "X-Hub-Signature" => "sha256=#{signature}"
      ).post(ENV.fetch("BLOG_WEBHOOK_URL"), body: payload_json)

      unless response.status.success?
        raise "Webhook failed: HTTP #{response.status} — #{response.body.to_s.truncate(200)}"
      end

      response
    end

    private

    def build_payload
      {
        event:          "transcript_ready",
        video_id:       @video.youtube_video_id,
        title:          @video.title,
        channel:        @video.youtube_channel.name,
        transcript_url: "#{ENV.fetch('APP_URL')}/api/v1/transcripts/#{@video.youtube_video_id}"
      }
    end

    def webhook_secret
      ENV.fetch("BLOG_WEBHOOK_SECRET")
    end
  end
end
