class CreatePlays < ActiveRecord::Migration[8.1]
  def change
    # 複合主キーで同じ人の二重加算を防ぐ
    create_table :plays, primary_key: [ :balloon_id, :user_id ] do |t|
      t.bigint :balloon_id, null: false
      t.bigint :user_id, null: false
      t.datetime :played_at, null: false
    end
    add_index :plays, :user_id
    add_foreign_key :plays, :balloons
    add_foreign_key :plays, :users
  end
end
