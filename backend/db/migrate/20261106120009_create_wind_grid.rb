class CreateWindGrid < ActiveRecord::Migration[8.1]
  def change
    # 他のテーブルとは結合しない
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
