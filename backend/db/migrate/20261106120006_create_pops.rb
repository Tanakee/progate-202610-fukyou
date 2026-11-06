class CreatePops < ActiveRecord::Migration[8.1]
  def change
    # 行があれば、その人には風船を流さない
    create_table :pops, primary_key: [ :balloon_id, :user_id ] do |t|
      t.bigint :balloon_id, null: false
      t.bigint :user_id, null: false
      t.datetime :popped_at, null: false
    end
    add_index :pops, :user_id
    add_foreign_key :pops, :balloons
    add_foreign_key :pops, :users
  end
end
