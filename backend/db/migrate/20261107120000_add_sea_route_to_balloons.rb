class AddSeaRouteToBalloons < ActiveRecord::Migration[8.1]
  def change
    # 航路と港は config/sea_routes.json の何番目かで持つ。どちらも変わらないデータなので、テーブルにしない
    add_column :balloons, :sea_route, :integer
    add_column :balloons, :boarded_at, :datetime
    add_column :balloons, :last_port, :integer
  end
end
