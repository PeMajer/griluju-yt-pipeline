class CreateYoutubeVideos < ActiveRecord::Migration[8.1]
  def change
    create_table :youtube_videos do |t|
      t.string     :youtube_video_id,   null: false
      t.references :youtube_channel,    null: false, foreign_key: true
      t.string     :title
      t.text       :description
      t.string     :video_url
      t.string     :thumbnail_url
      t.datetime   :published_at
      t.integer    :duration_seconds
      t.string     :processing_status,  null: false, default: "new"
      t.text       :failed_reason
      t.integer    :retry_count,        null: false, default: 0
      t.datetime   :webhook_sent_at
      t.boolean    :queued_for_blog,    null: false, default: false

      t.timestamps
    end

    add_index :youtube_videos, :youtube_video_id, unique: true
    add_index :youtube_videos, :processing_status
    add_index :youtube_videos, :webhook_sent_at
    add_index :youtube_videos, :queued_for_blog
    add_index :youtube_videos, [ :processing_status, :webhook_sent_at ], name: "idx_videos_status_webhook"
    add_index :youtube_videos, [ :processing_status, :updated_at ],      name: "idx_videos_status_updated"
  end
end
