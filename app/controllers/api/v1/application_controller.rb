module Api
  module V1
    class ApplicationController < ActionController::API
      before_action :authenticate_api_key!

      private

      def authenticate_api_key!
        provided = request.headers["X-Api-Key"].to_s
        expected = ENV.fetch("BLOG_API_KEY", "")

        unless ActiveSupport::SecurityUtils.secure_compare(provided, expected)
          render json: { error: "Unauthorized" }, status: :unauthorized
        end
      end
    end
  end
end
