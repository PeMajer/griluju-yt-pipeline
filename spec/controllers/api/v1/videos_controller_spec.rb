require "rails_helper"

RSpec.describe Api::V1::VideosController, type: :controller do
  let(:api_key) { "test-api-key" }
  let(:channel) { create(:youtube_channel) }

  before do
    stub_const("ENV", ENV.to_hash.merge("BLOG_API_KEY" => api_key))
    request.headers["X-Api-Key"] = api_key
  end

  describe "GET #index" do
    let!(:ready_video)   { create(:youtube_video, :transcript_ready, youtube_channel: channel) }
    let!(:new_video)     { create(:youtube_video, youtube_channel: channel, processing_status: "new") }
    let!(:webhook_video) do
      create(:youtube_video, :transcript_ready, youtube_channel: channel,
             webhook_sent_at: nil)
    end
    let!(:queued_video)  { create(:youtube_video, youtube_channel: channel, queued_for_blog: true) }

    context "bez filtrů" do
      before { get :index }

      it "vrátí HTTP 200" do
        expect(response).to have_http_status(:ok)
      end

      it "vrátí všechna videa" do
        json = JSON.parse(response.body)
        expect(json.size).to eq(YoutubeVideo.count)
      end
    end

    context "filtr status=transcript_ready" do
      before { get :index, params: { status: "transcript_ready" } }

      it "vrátí pouze transcript_ready videa" do
        json = JSON.parse(response.body)
        expect(json.map { |v| v["processing_status"] }.uniq).to eq([ "transcript_ready" ])
      end
    end

    context "filtr webhook_sent_at=null" do
      before do
        ready_video.update!(webhook_sent_at: Time.current)  # toto bude vyloučeno
        get :index, params: { webhook_sent_at: "null" }
      end

      it "vrátí jen videa bez webhook_sent_at" do
        json = JSON.parse(response.body)
        expect(json.all? { |v| v["webhook_sent_at"].nil? }).to be true
      end
    end

    context "filtr queued_for_blog=true" do
      before { get :index, params: { queued_for_blog: "true" } }

      it "vrátí pouze queued_for_blog videa" do
        json = JSON.parse(response.body)
        expect(json.all? { |v| v["queued_for_blog"] == true }).to be true
      end
    end

    context "kombinace filtrů status + webhook_sent_at" do
      before do
        get :index, params: { status: "transcript_ready", webhook_sent_at: "null" }
      end

      it "aplikuje oba filtry najednou" do
        json = JSON.parse(response.body)
        json.each do |v|
          expect(v["processing_status"]).to eq("transcript_ready")
          expect(v["webhook_sent_at"]).to be_nil
        end
      end
    end

    context "chybí autentizace" do
      before do
        request.headers["X-Api-Key"] = nil
        get :index
      end

      it "vrátí HTTP 401" do
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "PATCH #update" do
    let(:video) { create(:youtube_video, youtube_channel: channel, queued_for_blog: false) }

    context "platný request" do
      before do
        patch :update, params: { video_id: video.youtube_video_id, video: { queued_for_blog: true } }
      end

      it "vrátí HTTP 200" do
        expect(response).to have_http_status(:ok)
      end

      it "aktualizuje queued_for_blog" do
        expect(video.reload.queued_for_blog).to be true
      end
    end

    context "chybí povinný parametr video" do
      before { patch :update, params: { video_id: video.youtube_video_id } }

      it "vrátí HTTP 422" do
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "neexistující video" do
      it "vyhodí ActiveRecord::RecordNotFound" do
        expect do
          patch :update, params: { video_id: "nonexistent", video: { queued_for_blog: true } }
        end.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "chybí autentizace" do
      before do
        request.headers["X-Api-Key"] = "wrong"
        patch :update, params: { video_id: video.youtube_video_id, video: { queued_for_blog: true } }
      end

      it "vrátí HTTP 401" do
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
