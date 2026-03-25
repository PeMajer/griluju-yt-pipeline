class CreateYoutubeChannels < ActiveRecord::Migration[8.1]
  def change
    create_table :youtube_channels do |t|
      t.string   :name,             null: false
      t.string   :channel_id,       null: false
      t.string   :channel_url
      t.boolean  :active,           null: false, default: true
      t.jsonb    :tags,             null: false, default: []
      t.datetime :last_checked_at
      t.string   :default_language, null: false, default: "en"
      t.integer  :backfill_limit,   null: false, default: 40

      t.timestamps
    end

    add_index :youtube_channels, :channel_id, unique: true
    add_index :youtube_channels, :active
  end
end
