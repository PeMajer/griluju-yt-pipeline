require "rails_helper"

RSpec.describe Api::V1::TranscriptsController, type: :controller do
  let(:api_key) { "test-api-key" }

  before do
    stub_const("ENV", ENV.to_hash.merge("BLOG_API_KEY" => api_key))
    request.headers["X-Api-Key"] = api_key
  end

  describe "GET #show" do
    let(:channel)    { create(:youtube_channel, name: "Chud's BBQ") }
    let(:video) do
      create(:youtube_video, :transcript_ready,
             youtube_channel: channel,
             youtube_video_id: "abc123",
             title: "Beef Ribs 101",
             published_at: Time.parse("2024-06-01 12:00:00 UTC"))
    end
    let!(:transcript) do
      create(:video_transcript,
             youtube_video: video,
             language: "en",
             source_type: "manual_subtitles",
             cleaned_transcript: "Smoke them beef ribs low and slow.")
    end

    context "platný video_id s transkriptem" do
      before { get :show, params: { video_id: "abc123" } }

      it "vrátí HTTP 200" do
        expect(response).to have_http_status(:ok)
      end

      it "vrátí správná pole" do
        json = JSON.parse(response.body)
        expect(json).to include(
          "video_id"   => "abc123",
          "title"      => "Beef Ribs 101",
          "channel"    => "Chud's BBQ",
          "language"   => "en",
          "source_type" => "manual_subtitles"
        )
      end

      it "vrátí cleaned_transcript" do
        json = JSON.parse(response.body)
        expect(json["cleaned_transcript"]).to eq("Smoke them beef ribs low and slow.")
      end
    end

    context "video existuje, ale nemá transkript" do
      before do
        video_no_transcript = create(:youtube_video, youtube_channel: channel, youtube_video_id: "notranscript")
        get :show, params: { video_id: "notranscript" }
      end

      it "vrátí HTTP 404" do
        expect(response).to have_http_status(:not_found)
      end
    end

    context "neexistující video_id" do
      it "vyhodí ActiveRecord::RecordNotFound" do
        expect { get :show, params: { video_id: "nonexistent" } }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "chybí autentizace" do
      before do
        request.headers["X-Api-Key"] = "wrong-key"
        get :show, params: { video_id: "abc123" }
      end

      it "vrátí HTTP 401" do
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
