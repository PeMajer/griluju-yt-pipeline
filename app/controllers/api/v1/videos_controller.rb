module Api
  module V1
    class VideosController < ApplicationController
      def index
        videos = YoutubeVideo.includes(:youtube_channel, :video_transcript)
        videos = apply_filters(videos)

        render json: videos.map { |v| video_json(v) }
      end

      def update
        video = YoutubeVideo.find_by!(youtube_video_id: params[:video_id])
        video.update!(video_params)
        render json: { status: "updated" }
      rescue ActionController::ParameterMissing => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def apply_filters(scope)
        scope = scope.where(processing_status: params[:status])  if params[:status].present?
        scope = scope.where(webhook_sent_at: nil)                if params[:webhook_sent_at] == "null"
        scope = scope.where(queued_for_blog: true)                if params[:queued_for_blog] == "true"
        scope = scope.where(queued_for_blog: false)               if params[:queued_for_blog] == "false"
        scope
      end

      def video_params
        params.require(:video).permit(:queued_for_blog)
      end

      def video_json(video)
        {
          video_id:          video.youtube_video_id,
          title:             video.title,
          channel:           video.youtube_channel.name,
          processing_status: video.processing_status,
          webhook_sent_at:   video.webhook_sent_at,
          queued_for_blog:   video.queued_for_blog
        }
      end
    end
  end
end
