FactoryBot.define do
  factory :youtube_channel do
    name             { "Test BBQ Channel" }
    sequence(:channel_id) { |n| "UC#{n.to_s.rjust(22, '0')}" }
    channel_url      { "https://youtube.com/@testbbq" }
    active           { true }
    tags             { [] }
    default_language { "en" }
    backfill_limit   { 30 }
  end
end
