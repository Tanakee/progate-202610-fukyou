class DropPops < ActiveRecord::Migration[8.1]
  def change
    drop_table :pops, primary_key: [ :balloon_id, :user_id ] do |t|
      t.references :balloon, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true
      t.datetime :popped_at, null: false
    end
  end
end
