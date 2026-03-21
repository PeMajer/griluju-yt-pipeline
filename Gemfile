source "https://rubygems.org"

ruby "3.3.8"

gem "rails", "~> 8.1.2"
gem "pg", "~> 1.5"
gem "puma", ">= 5.0"
gem "bootsnap", require: false

# Background jobs
gem "sidekiq", "~> 7.0"
gem "sidekiq-cron", "~> 2.0"
gem "connection_pool", "~> 2.4"  # 3.0.x změnilo API TimedStack#pop, nekompatibilní se Sidekiq 7.3.x

# HTTP klient pro webhook notifikace
gem "http", "~> 5.2"

# RSS/Atom parser pro YouTube Atom feeds (stdlib rss špatně parsuje yt: namespace)
gem "feedjira", "~> 3.2"

group :development, :test do
  gem "debug", platforms: %i[mri mingw x64_mingw], require: "debug/prelude"
  gem "rspec-rails", "~> 7.0"
  gem "factory_bot_rails"
  gem "faker"
end

group :development do
  gem "rubocop-rails-omakase", require: false
end

group :test do
  gem "webmock"
  gem "shoulda-matchers"
end
