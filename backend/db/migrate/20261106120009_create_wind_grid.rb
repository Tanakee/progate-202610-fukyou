class CreateWindGrid < ActiveRecord::Migration[8.1]
  def change
    # 格子点と予報の有効時刻ごとに1行。他のテーブルと結合しないので、id も外部キーも持たない
    create_table :wind_grid, primary_key: [ :lat, :lng, :valid_time ] do |t|
      t.float :lat, null: false
      t.float :lng, null: false
      t.datetime :valid_time, null: false
      t.float :speed_east, null: false
      t.float :speed_north, null: false
      t.datetime :fetched_at, null: false
    end
  end
end
