class CreatePlays < ActiveRecord::Migration[8.1]
  def change
    # 複合主キーで、同じ人が同じ風船の回数を2回以上増やせないようにする
    create_table :plays, primary_key: [ :balloon_id, :user_id ] do |t|
      # balloon_id は主キーの先頭の列なので、主キーの索引で検索できる
      t.references :balloon, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true
      t.datetime :played_at, null: false
    end
  end
end
