class AddDailyLimitExemptToFavorites < ActiveRecord::Migration[8.1]
  def change
    add_column :favorites, :daily_limit_exempt, :boolean, default: false, null: false

    remove_index :favorites, [ :user_id, :collected_on ], unique: true
    add_index :favorites, [ :user_id, :collected_on ], unique: true,
      where: "daily_limit_exempt = false"
  end
end
