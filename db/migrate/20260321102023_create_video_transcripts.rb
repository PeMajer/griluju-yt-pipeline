class CreateVideoTranscripts < ActiveRecord::Migration[8.1]
  def change
    create_table :video_transcripts do |t|
      t.references :youtube_video,           null: false, foreign_key: true
      t.string     :source_type
      t.text       :raw_transcript
      t.text       :cleaned_transcript
      t.string     :language
      t.boolean    :available,               null: false, default: false
      t.integer    :word_count,              null: false, default: 0
      t.integer    :transcript_quality_score, null: false, default: 0
      t.string     :captions_source_detail

      t.timestamps
    end

    add_index :video_transcripts, :source_type
    add_index :video_transcripts, :language
  end
end
