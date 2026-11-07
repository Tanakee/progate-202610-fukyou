class AddSeaRouteToBalloons < ActiveRecord::Migration[8.1]
  def change
    # 港は config/sea_routes.json の何番目かで持つ。変わらないデータなので、テーブルにしない。
    # 通る道は出た港と行き先の港から毎回求められるので、持たない
    add_column :balloons, :last_port, :integer
    add_column :balloons, :bound_for, :integer
    add_column :balloons, :boarded_at, :datetime
  end
end
