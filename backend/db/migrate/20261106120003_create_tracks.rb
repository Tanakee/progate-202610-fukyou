class CreateTracks < ActiveRecord::Migration[8.1]
  def change
    create_table :tracks, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :title, null: false
      t.string :artist, null: false
      t.string :mp3_url, null: false

      t.timestamps
    end
  end
end
