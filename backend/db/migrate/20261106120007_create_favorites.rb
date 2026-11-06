class CreateFavorites < ActiveRecord::Migration[8.1]
  def change
    create_table :favorites do |t|
      # user_id での検索は、下の (user_id, collected_on) の索引で足りる
      t.references :user, null: false, foreign_key: true, index: false
      # 1つの風船を回収できるのは1人だけ
      t.references :balloon, null: false, foreign_key: true, index: { unique: true }
      # 回収した日。日本時間の日付を入れる
      t.date :collected_on, null: false

      t.timestamps
    end

    # 回収は1日1回
    add_index :favorites, [ :user_id, :collected_on ], unique: true
  end
end
