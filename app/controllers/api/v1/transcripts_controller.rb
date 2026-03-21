module Api
  module V1
    class TranscriptsController < ApplicationController
      def show
        video = YoutubeVideo.find_by!(youtube_video_id: params[:video_id])
        transcript = video.video_transcript

        if transcript.nil?
          render json: { error: "Transcript not found" }, status: :not_found
          return
        end

        render json: {
          video_id:           video.youtube_video_id,
          title:              video.title,
          channel:            video.youtube_channel.name,
          published_at:       video.published_at,
          language:           transcript.language,
          source_type:        transcript.source_type,
          cleaned_transcript: transcript.cleaned_transcript
        }
      end
    end
  end
end
