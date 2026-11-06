class CreateBalloons < ActiveRecord::Migration[8.1]
  def change
    create_table :balloons do |t|
      t.references :owner, null: false, foreign_key: { to_table: :users }, index: false
      t.references :track, null: false, foreign_key: true
      t.string :status, null: false, default: "flying"
      t.string :origin_label, null: false
      t.float :origin_lat, null: false
      t.float :origin_lng, null: false
      t.float :lat, null: false
      t.float :lng, null: false
      t.float :speed_east, null: false, default: 0
      t.float :speed_north, null: false, default: 0
      t.integer :play_count, null: false, default: 0
      t.datetime :launched_at, null: false
      t.datetime :ended_at

      t.timestamps
    end

    add_index :balloons, :owner_id
    # 飛行中の風船は1人1個まで
    add_index :balloons, :owner_id, unique: true, where: "status = 'flying'",
              name: "index_balloons_on_owner_id_flying"
    # 地図の配信で飛行中の風船を引く
    add_index :balloons, :status

    add_check_constraint :balloons, "status IN ('flying', 'collected', 'lost')", name: "balloons_status_check"
    add_check_constraint :balloons, "play_count >= 0", name: "balloons_play_count_check"
  end
end
