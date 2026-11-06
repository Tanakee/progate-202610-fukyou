class CreateJourneys < ActiveRecord::Migration[8.1]
  def change
    create_table :journeys, id: :uuid do |t|
      t.references :balloon, null: false, foreign_key: true, type: :uuid, index: { unique: true }
      t.string :end_reason, null: false
      t.string :end_label, null: false
      t.float :end_lat, null: false
      t.float :end_lng, null: false
      t.integer :duration_seconds, null: false
      # 旅が終わった時点の回数
      t.integer :play_count, null: false

      t.timestamps
    end
    add_check_constraint :journeys, "duration_seconds >= 0", name: "journeys_duration_seconds_check"
    add_check_constraint :journeys, "play_count >= 0", name: "journeys_play_count_check"
  end
end
