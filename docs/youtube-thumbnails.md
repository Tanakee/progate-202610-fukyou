# YouTubeのサムネイル

`POST /tracks` に `youtube_url` を送ると、yt-dlpで音声とサムネイルを取得します。
サムネイルはffmpegでJPEGに変換し、音声と同じActive Storageの保存先へ添付します。
既存のActive Storageテーブルを使うため、マイグレーションは不要です。

```powershell
$body = @{ youtube_url = "https://youtu.be/U6BDbXIah-Y" } | ConvertTo-Json
$track = Invoke-RestMethod -Method Post -Uri "http://localhost:3000/tracks" -Headers @{ Authorization = "Bearer $token" } -ContentType "application/json" -Body $body
$track
Start-Process $track.thumbnail_url
```

曲の作成、単体取得、自分の曲一覧、お気に入り内の曲情報に `thumbnail_url` が含まれます。
例: `http://localhost:3000/tracks/7/thumbnail`

このURLは認証なしで保存した画像を返します。外部のYouTube画像URLや
Docker内部のMinIOへリダイレクトしません。
画像のない既存曲と音声直接アップロードでは `thumbnail_url` は `null` です。
既存曲への画像の追加取得は行いません。

YouTubeのサムネイル取得・変換に失敗した場合、取り込みは422で失敗し、曲は作成しません。
一時ファイルは処理終了時に削除されます。

自動テストではYouTubeへの外部通信をテスト用の実行ファイルに置き換え、
画像・音声の保存、レスポンス、画像取得、失敗時の後始末を確認します。
実際のYouTubeとの接続は上のコマンドで別途確認してください。
