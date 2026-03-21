FactoryBot.define do
  factory :video_transcript do
    association :youtube_video
    source_type        { "manual_subtitles" }
    raw_transcript     { "This is a raw transcript." }
    cleaned_transcript { "This is a clean transcript." }
    language           { "en" }
    available          { true }
  end
end
