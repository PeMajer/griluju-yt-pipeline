require "rails_helper"

RSpec.describe NotifyBlogJob do
  let(:channel)    { create(:youtube_channel) }
  let(:video)      { create(:youtube_video, :transcript_ready, youtube_channel: channel) }

  subject(:job) { described_class.new }

  describe "#perform" do
    context "úspěšné odeslání" do
      before do
        allow(Blog::WebhookService).to receive(:call)
      end

      it "volá WebhookService" do
        job.perform(video.id)
        expect(Blog::WebhookService).to have_received(:call).with(video)
      end

      it "nastaví webhook_sent_at" do
        freeze_time do
          job.perform(video.id)
          expect(video.reload.webhook_sent_at).to be_within(1.second).of(Time.current)
        end
      end
    end

    context "WebhookService selže" do
      before do
        allow(Blog::WebhookService).to receive(:call).and_raise(RuntimeError, "Webhook failed: HTTP 503")
      end

      it "propaguje chybu pro Sidekiq retry" do
        expect { job.perform(video.id) }.to raise_error(RuntimeError, /Webhook failed/)
      end

      it "nenastaví webhook_sent_at" do
        expect { job.perform(video.id) }.to raise_error(RuntimeError)
        expect(video.reload.webhook_sent_at).to be_nil
      end
    end
  end
end
