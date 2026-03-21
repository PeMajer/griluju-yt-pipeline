require "rails_helper"

RSpec.describe Blog::WebhookService do
  let(:channel)    { create(:youtube_channel, name: "Mad Scientist BBQ") }
  let(:video)      { create(:youtube_video, :transcript_ready, youtube_channel: channel, title: "12h Brisket") }
  let(:transcript) { create(:video_transcript, youtube_video: video) }

  subject(:service) { described_class.new(video) }

  before do
    stub_const("ENV", ENV.to_hash.merge(
      "BLOG_API_KEY"        => "test-api-key",
      "BLOG_WEBHOOK_URL"    => "https://blog.example.com/webhooks/youtube",
      "BLOG_WEBHOOK_SECRET" => "super-secret",
      "APP_URL"             => "https://pipeline.example.com"
    ))
    transcript # ensure transcript exists
  end

  describe "#call" do
    let(:ok_response)   { double("response", status: double(success?: true)) }
    let(:fail_response) { double("response", status: double(success?: false), body: double(to_s: "Internal Server Error")) }

    context "úspěšný webhook" do
      before do
        allow(HTTP).to receive_message_chain(:headers, :post).and_return(ok_response)
      end

      it "provede POST na BLOG_WEBHOOK_URL" do
        headers_double = double
        allow(HTTP).to receive(:headers).and_return(headers_double)
        allow(headers_double).to receive(:post).and_return(ok_response)

        service.call

        expect(headers_double).to have_received(:post).with(
          "https://blog.example.com/webhooks/youtube",
          body: anything
        )
      end

      it "odesílá X-Api-Key hlavičku" do
        captured_headers = nil
        allow(HTTP).to receive(:headers) do |h|
          captured_headers = h
          double.tap { |d| allow(d).to receive(:post).and_return(ok_response) }
        end

        service.call
        expect(captured_headers["X-Api-Key"]).to eq("test-api-key")
      end

      it "odesílá HMAC-SHA256 signaturu" do
        captured_headers = nil
        captured_body    = nil

        allow(HTTP).to receive(:headers) do |h|
          captured_headers = h
          double.tap do |d|
            allow(d).to receive(:post) do |_url, body:|
              captured_body = body
              ok_response
            end
          end
        end

        service.call

        expected_sig = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", "super-secret", captured_body)
        expect(captured_headers["X-Hub-Signature"]).to eq(expected_sig)
      end

      it "payload obsahuje správná pole" do
        captured_body = nil
        allow(HTTP).to receive(:headers).and_return(
          double.tap do |d|
            allow(d).to receive(:post) do |_url, body:|
              captured_body = body
              ok_response
            end
          end
        )

        service.call
        payload = JSON.parse(captured_body)

        expect(payload).to include(
          "event"   => "transcript_ready",
          "video_id" => video.youtube_video_id,
          "title"   => "12h Brisket",
          "channel" => "Mad Scientist BBQ"
        )
        expect(payload["transcript_url"]).to include(video.youtube_video_id)
      end
    end

    context "blog vrátí chybový HTTP status" do
      before do
        allow(HTTP).to receive(:headers).and_return(
          double.tap { |d| allow(d).to receive(:post).and_return(fail_response) }
        )
      end

      it "vyhodí RuntimeError s HTTP statusem" do
        expect { service.call }.to raise_error(RuntimeError, /Webhook failed/)
      end
    end
  end
end
