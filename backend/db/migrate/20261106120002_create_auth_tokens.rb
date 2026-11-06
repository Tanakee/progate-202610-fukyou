class CreateAuthTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :auth_tokens, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :token_digest, null: false

      t.timestamps
    end
    add_index :auth_tokens, :token_digest, unique: true
  end
end
