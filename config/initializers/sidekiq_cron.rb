Sidekiq.configure_server do |config|
  config.on(:startup) do
    schedule = [
      {
        "name"  => "Channel Polling",
        "cron"  => "0 */6 * * *",
        "class" => "ChannelPollingJob"
      }
    ]
    Sidekiq::Cron::Job.load_from_array!(schedule)
  end
end
