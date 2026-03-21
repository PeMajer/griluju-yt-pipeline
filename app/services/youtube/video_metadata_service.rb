module Youtube
  class VideoMetadataService
    YT_DLP_PATH = "/opt/pyenv/bin/yt-dlp".freeze

    def self.call(video)
      new(video).call
    end

    def initialize(video)
      @video = video
    end

    def call
      stdout, stderr, status = Open3.capture3(
        YT_DLP_PATH,
        "--dump-json",
        "--skip-download",
        "--no-warnings",
        @video.video_url
      )

      unless status.success?
        raise "yt-dlp failed for #{@video.youtube_video_id}: #{stderr.strip}"
      end

      JSON.parse(stdout)
    end
  end
end
