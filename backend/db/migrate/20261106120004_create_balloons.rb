class CreateBalloons < ActiveRecord::Migration[8.1]
  def change
    create_table :balloons do |t|
      # 飛ばした人。曲の持ち主（tracks.user_id）と同じ人になる
      t.references :user, null: false, foreign_key: true
      t.references :track, null: false, foreign_key: true
      t.string :status, null: false, default: "flying"
      t.string :origin_label, null: false
      t.float :origin_lat, null: false
      t.float :origin_lng, null: false
      # lat / lng / speed_* / moved_at は、定期処理が5秒ごとに飛行中の行だけを更新する。
      # 索引を付けると HOT 更新が効かなくなるので、これらの列には索引を付けない
      t.float :lat, null: false
      t.float :lng, null: false
      t.float :speed_east, null: false, default: 0
      t.float :speed_north, null: false, default: 0
      # lat / lng を計算した日時。次の位置は、ここからの実際の経過時間で計算する
      t.datetime :moved_at, null: false
      t.integer :play_count, null: false, default: 0
      t.datetime :launched_at, null: false
      t.datetime :ended_at

      t.timestamps
    end

    # 飛行中の風船は1人1個まで
    add_index :balloons, :user_id, unique: true, where: "status = 'flying'",
              name: "index_balloons_on_user_id_flying"
    # 定期処理と地図の配信は、飛行中の風船だけを読む
    add_index :balloons, :id, where: "status = 'flying'", name: "index_balloons_flying"

    add_check_constraint :balloons, "status IN ('flying', 'collected', 'lost')", name: "balloons_status_check"
    add_check_constraint :balloons, "play_count >= 0", name: "balloons_play_count_check"
  end
end
