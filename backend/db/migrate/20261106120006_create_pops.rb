class CreatePops < ActiveRecord::Migration[8.1]
  def change
    # 複合主キーで1人1回にする。行があれば、その人にはその風船を流さない
    create_table :pops, primary_key: [ :balloon_id, :user_id ] do |t|
      # balloon_id は主キーの先頭の列なので、主キーの索引で検索できる
      t.references :balloon, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true
      t.datetime :popped_at, null: false
    end
  end
end
