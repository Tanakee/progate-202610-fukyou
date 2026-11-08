class RemoveMp3UrlFromTracks < ActiveRecord::Migration[8.1]
  def change
    # 保存した URL を返さないのは、ストレージを直接指す署名付き URL には期限があり、返すたびに作り直す必要があるから
    remove_column :tracks, :mp3_url, :string, null: false
  end
end
