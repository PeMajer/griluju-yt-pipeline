require "rails_helper"

RSpec.describe Youtube::RssPollerService do
  let(:channel) { create(:youtube_channel, channel_id: "UCxyz123") }

  subject(:service) { described_class.new(channel) }

  SAMPLE_RSS = <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom"
          xmlns:yt="http://www.youtube.com/xml/schemas/2015"
          xmlns:media="http://search.yahoo.com/mrss/">
      <entry>
        <yt:videoId>abc123</yt:videoId>
        <title>Amazing Brisket Cook</title>
        <link rel="alternate" href="https://www.youtube.com/watch?v=abc123"/>
        <published>2024-01-15T12:00:00+00:00</published>
        <media:group>
          <media:thumbnail url="https://i.ytimg.com/vi/abc123/hq720.jpg"/>
        </media:group>
      </entry>
      <entry>
        <yt:videoId>def456</yt:videoId>
        <title>Pulled Pork Tutorial</title>
        <link rel="alternate" href="https://www.youtube.com/watch?v=def456"/>
        <published>2024-01-10T12:00:00+00:00</published>
      </entry>
    </feed>
  XML

  before do
    allow(HTTP).to receive(:get).and_return(double(to_s: SAMPLE_RSS))
    allow(ProcessVideoJob).to receive(:perform_later)
  end

  describe "#call" do
    it "vytvoří YoutubeVideo záznamy pro všechna videa v RSS" do
      expect { service.call }.to change(YoutubeVideo, :count).by(2)
    end

    it "nastaví processing_status na new" do
      service.call
      expect(YoutubeVideo.pluck(:processing_status).uniq).to eq([ "new" ])
    end

    it "spustí ProcessVideoJob pro každé nové video" do
      service.call
      expect(ProcessVideoJob).to have_received(:perform_later).twice
    end

    it "správně uloží video_id z URL" do
      service.call
      expect(YoutubeVideo.pluck(:youtube_video_id)).to contain_exactly("abc123", "def456")
    end

    it "uloží published_at jako UTC" do
      service.call
      video = YoutubeVideo.find_by(youtube_video_id: "abc123")
      expect(video.published_at).to eq(Time.parse("2024-01-15T12:00:00+00:00").utc)
    end

    context "video již existuje v DB (idempotence)" do
      before { create(:youtube_video, youtube_video_id: "abc123", youtube_channel: channel) }

      it "nevytvoří duplicitní záznam" do
        expect { service.call }.to change(YoutubeVideo, :count).by(1)
      end

      it "nespustí ProcessVideoJob pro existující video" do
        service.call
        expect(ProcessVideoJob).to have_received(:perform_later).once
      end
    end

    context "race condition — RecordNotUnique" do
      it "tiše přeskočí záznam a pokračuje" do
        call_count = 0
        allow(YoutubeVideo).to receive(:find_or_create_by!) do
          call_count += 1
          raise ActiveRecord::RecordNotUnique if call_count == 1
          create(:youtube_video, youtube_channel: channel)
        end

        expect { service.call }.not_to raise_error
      end
    end

    context "entry s neplatnou URL" do
      let(:bad_rss) do
        <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <feed xmlns="http://www.w3.org/2005/Atom">
            <entry>
              <title>Bad entry</title>
              <link rel="alternate" href="not a url :::"/>
              <published>2024-01-15T12:00:00+00:00</published>
            </entry>
          </feed>
        XML
      end

      before { allow(HTTP).to receive(:get).and_return(double(to_s: bad_rss)) }

      it "přeskočí entry s neplatnou URL a neselže" do
        expect { service.call }.not_to raise_error
        expect(YoutubeVideo.count).to eq(0)
      end
    end

    context "HTTP chyba" do
      before { allow(HTTP).to receive(:get).and_raise(HTTP::Error, "Connection refused") }

      it "vyhodí chybu dál" do
        expect { service.call }.to raise_error(HTTP::Error)
      end
    end
  end
end
