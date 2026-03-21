# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_21_102023) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "video_transcripts", force: :cascade do |t|
    t.boolean "available", default: false, null: false
    t.string "captions_source_detail"
    t.text "cleaned_transcript"
    t.datetime "created_at", null: false
    t.string "language"
    t.text "raw_transcript"
    t.string "source_type"
    t.integer "transcript_quality_score", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "word_count", default: 0, null: false
    t.bigint "youtube_video_id", null: false
    t.index ["language"], name: "index_video_transcripts_on_language"
    t.index ["source_type"], name: "index_video_transcripts_on_source_type"
    t.index ["youtube_video_id"], name: "index_video_transcripts_on_youtube_video_id"
  end

  create_table "youtube_channels", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "backfill_limit", default: 30, null: false
    t.string "channel_id", null: false
    t.string "channel_url"
    t.datetime "created_at", null: false
    t.string "default_language", default: "en", null: false
    t.datetime "last_checked_at"
    t.string "name", null: false
    t.jsonb "tags", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_youtube_channels_on_active"
    t.index ["channel_id"], name: "index_youtube_channels_on_channel_id", unique: true
  end

  create_table "youtube_videos", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "duration_seconds"
    t.text "failed_reason"
    t.string "processing_status", default: "new", null: false
    t.datetime "published_at"
    t.boolean "queued_for_blog", default: false, null: false
    t.integer "retry_count", default: 0, null: false
    t.string "thumbnail_url"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "video_url"
    t.datetime "webhook_sent_at"
    t.bigint "youtube_channel_id", null: false
    t.string "youtube_video_id", null: false
    t.index ["processing_status", "updated_at"], name: "idx_videos_status_updated"
    t.index ["processing_status", "webhook_sent_at"], name: "idx_videos_status_webhook"
    t.index ["processing_status"], name: "index_youtube_videos_on_processing_status"
    t.index ["queued_for_blog"], name: "index_youtube_videos_on_queued_for_blog"
    t.index ["webhook_sent_at"], name: "index_youtube_videos_on_webhook_sent_at"
    t.index ["youtube_channel_id"], name: "index_youtube_videos_on_youtube_channel_id"
    t.index ["youtube_video_id"], name: "index_youtube_videos_on_youtube_video_id", unique: true
  end

  add_foreign_key "video_transcripts", "youtube_videos"
  add_foreign_key "youtube_videos", "youtube_channels"
end
