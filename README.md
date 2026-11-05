## 開発環境の起動

Docker Desktop を起動し、リポジトリ直下で実行します。

```sh
docker compose up
```

初回はイメージの取得と gem のインストールに時間がかかります。
DB の準備（`db:prepare`）は Rails の起動前に自動で実行されます。

### 動作確認

ブラウザで `http://localhost:3000/up` を開き、緑の画面が表示されれば Rails は起動しています。

別のターミナルから、Rails と PostgreSQL の接続を確認できます。

```sh
docker compose exec app ruby bin/rails runner 'puts ActiveRecord::Base.connection.select_value(%q[SELECT 1])'
```

`1` が表示されれば接続成功です。

### 停止

起動中のターミナルで `Ctrl+C` を押し、次を実行します。

```sh
docker compose down
```

DB のデータは Docker のボリュームに保存され、次回の起動時にも使われます。