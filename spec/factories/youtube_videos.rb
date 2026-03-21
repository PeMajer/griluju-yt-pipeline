FactoryBot.define do
  factory :youtube_video do
    association :youtube_channel
    sequence(:youtube_video_id) { |n| "dQw4w9WgXc#{n}" }
    title             { "Test BBQ Video" }
    video_url         { "https://www.youtube.com/watch?v=dQw4w9WgXc0" }
    published_at      { 1.day.ago }
    processing_status { "new" }
    retry_count       { 0 }
    queued_for_blog   { false }

    trait :transcript_ready do
      processing_status { "transcript_ready" }
    end

    trait :failed do
      processing_status { "failed" }
      failed_reason     { "yt-dlp error" }
    end

    trait :skipped do
      processing_status { "skipped" }
      failed_reason     { "short_video" }
    end
  end
end
