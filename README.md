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

### テスト

```sh
docker compose exec app ruby bin/rails test
```

テストは `fukyou_test` を使います。開発用の `fukyou_development` には影響しません。
DB の接続先は `compose.yaml` の `DB_HOST` / `DB_USERNAME` / `DB_PASSWORD` で指定しています（`DATABASE_URL` は全ての環境に効いてしまうため使いません）。

## データベース

テーブルは `backend/db/migrate/` のマイグレーションで作ります。図は `docs/diagrams/erd-data-model-20261102-100000/data-model.html` です。

- 主キーは Rails 標準の自動採番（bigint）です
- 時刻は DB に UTC で保存し、アプリは `Asia/Tokyo` で扱います（1日の区切りは日本時間の0時）
- パスワードは `argon2` gem でハッシュ化して `users.password_digest` に保存します（`has_secure_password` は使いません）

### マイグレーションの実行

```sh
docker compose exec app ruby bin/rails db:migrate
```

### DB を作り直す

```sh
docker compose exec app ruby bin/rails db:drop db:create db:migrate
```

空の DB に `db:migrate` を実行すると、Rails は先に `backend/db/schema.rb` を読み込みます。
マイグレーションを書き換えたときは、`schema.rb` を消してから作り直してください。

## API 仕様（Swagger UI）

API 仕様は `backend/openapi/swagger.yml` にあります。リポジトリ直下で次を実行し、`http://localhost:8080` を開くと Swagger UI で読めます。

```sh
docker run --rm -p 8080:8080 -e SWAGGER_JSON=/spec/swagger.yml -v "$PWD/backend/openapi:/spec" swaggerapi/swagger-ui
```

認証が必要な API を試すときは、ログインで返った `token` を右上の **Authorize** に入れます。

## JSON の描画

API 専用の Rails なので、ビューは erb ではなく jbuilder（`app/views/**/*.json.jbuilder`）で書きます。

## 図の作り直し

`docs/diagrams/` の図は [archify](https://github.com/tt-a1i/archify) で作っています。各フォルダの `candidate.json` を直してから、`docs/` で次を実行します。

```sh
node <archifyの場所>/archify/bin/archify.mjs render erd diagrams/erd-data-model-20261102-100000/candidate.json diagrams/erd-data-model-20261102-100000/data-model.html --quality showcase
```

## 定期処理と WebSocket

`docker compose up` で、Web（`app`）とは別に2つの定期処理のコンテナが起動します。

| コンテナ | rake タスク | 内容 |
| --- | --- | --- |
| `wind` | `wind:fetch` | Open-Meteo から、日本周辺の1度格子（837地点）の風（地上10m、m/s）を、取得がいちばん古い100地点ずつ20分ごとに取得して `wind_grid` に保存する。一周は約3時間。まだ一度も取得していない地点があるうちは1分ごとに取得する |
| `balloons` | `balloons:move` | 保存済みの風データで、飛行中の風船を5秒ごとに動かし、`/ws` の `BalloonsChannel` へ `balloons.snapshot` を配信する。日本の排他的経済水域（EEZ）の外へ出た風船は割れる（`status` が `lost` になる） |

- Open-Meteo の無料枠は地点の数で数え、1分に600、1時間に5,000、1日に10,000までです。20分ごとに100地点なら1日7,200で収まります
- 速度の倍率は `compose.yaml` の `SPEED_SCALE` で変えられます（変えたら `docker compose up -d` で作り直す）
- どちらの定期処理も advisory lock で1プロセスだけが動きます。落ちたら compose が再起動します
- ログはエラーだけが出ます（`docker compose logs -f wind balloons`）。SQL などの詳しいログは `backend/log/development.log` にあります

届くデータは、`docs/websocket-viewer.html` をブラウザで開くと確かめられます。`/ws` に接続して `BalloonsChannel` を購読し、届いたメッセージの生データ、最新の snapshot の表、地図上の風船を表示します。

### 日本の排他的経済水域のデータ

`backend/config/japan_eez.json` は、[Marine Regions](https://www.marineregions.org/) の Maritime Boundaries and Exclusive Economic Zones（200NM）version 12（CC BY 4.0）から作りました。日本の EEZ に加え、北方領土・尖閣諸島・竹島周辺の主張の重なる海域と、日韓の共同開発区域を含みます。EEZ の形は陸地が穴になっているので外側の輪だけを使い（陸地も中に含める）、0.02度（約2 km）で間引いています。
