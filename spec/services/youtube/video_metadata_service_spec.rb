require "rails_helper"

RSpec.describe Youtube::VideoMetadataService do
  let(:video) { create(:youtube_video) }

  subject(:service) { described_class.new(video) }

  SAMPLE_METADATA = {
    "title"       => "Brisket Low and Slow",
    "description" => "12 hour brisket cook",
    "thumbnail"   => "https://i.ytimg.com/vi/abc123/hq720.jpg",
    "duration"    => 7200,
    "live_status" => "not_live",
    "webpage_url" => "https://www.youtube.com/watch?v=abc123"
  }.freeze

  describe "#call" do
    context "úspěšné volání yt-dlp" do
      before do
        ok = instance_double(Process::Status, success?: true)
        allow(Open3).to receive(:capture3).and_return([ SAMPLE_METADATA.to_json, "", ok ])
      end

      it "vrátí hash s metadaty" do
        result = service.call
        expect(result["title"]).to eq("Brisket Low and Slow")
      end

      it "volá yt-dlp se správnými argumenty" do
        service.call
        expect(Open3).to have_received(:capture3).with(
          Youtube::VideoMetadataService::YT_DLP_PATH,
          "--dump-json",
          "--skip-download",
          "--no-warnings",
          video.video_url
        )
      end
    end

    context "yt-dlp selže" do
      before do
        fail = instance_double(Process::Status, success?: false)
        allow(Open3).to receive(:capture3).and_return([ "", "ERROR: Video unavailable", fail ])
      end

      it "vyhodí RuntimeError" do
        expect { service.call }.to raise_error(RuntimeError, /yt-dlp failed/)
      end
    end

    context "yt-dlp vrátí nevalidní JSON" do
      before do
        ok = instance_double(Process::Status, success?: true)
        allow(Open3).to receive(:capture3).and_return([ "not json {{{", "", ok ])
      end

      it "vyhodí JSON::ParserError" do
        expect { service.call }.to raise_error(JSON::ParserError)
      end
    end
  end
end
