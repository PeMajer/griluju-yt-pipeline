require "sidekiq/web"
require "sidekiq/cron/web"

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Sidekiq Web UI chráněno HTTP Basic Auth
  Sidekiq::Web.use(Rack::Auth::Basic) do |username, password|
    ActiveSupport::SecurityUtils.secure_compare(
      ::Digest::SHA256.hexdigest(username),
      ::Digest::SHA256.hexdigest(ENV.fetch("SIDEKIQ_WEB_USERNAME", "admin"))
    ) &
    ActiveSupport::SecurityUtils.secure_compare(
      ::Digest::SHA256.hexdigest(password),
      ::Digest::SHA256.hexdigest(ENV.fetch("SIDEKIQ_WEB_PASSWORD", "changeme"))
    )
  end
  mount Sidekiq::Web => "/sidekiq"

  namespace :api do
    namespace :v1 do
      resources :videos,      only: [ :index, :update ], param: :video_id
      resources :transcripts, only: [ :show ],           param: :video_id
    end
  end
end
