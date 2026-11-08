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

## 音声の保存先（MinIO）

曲の音声は Active Storage で S3 互換の MinIO に保存します。`docker compose up` で一緒に起動し、初回は MinIO をソースからビルドするので数分かかります（コミュニティ版の公式イメージは配布が止まっています）。

- アプリには、MinIO を直接指す署名付き URL（1日有効）を返します。Rails を通さず、Range リクエストで先頭から少しずつ読んで再生を始められます
- 署名付き URL のホスト名は `minio.localhost:9000` です。Mac（シミュレーター）では `*.localhost` が自分自身を指し、compose の中では MinIO の別名になっているので、どちらからも同じ URL で届きます。実機からは届きません
- アップロードされた音声は、ffmpeg で 128kbps の固定ビットレートの mp3 にし、ジャケット画像を除いて保存します
- 保存したファイルは `http://localhost:9001`（ユーザー名・パスワードとも `minioadmin`）で見られます

```sh
curl -I -H "Range: bytes=0-1023" "<mp3_url>"   # 206 Partial Content が返れば Range で読める
```

## 監視（SRE）

`docker compose up` で、監視の仕組み（`sre/`）も一緒に起動します。管理画面は Grafana の `http://localhost:3001` です（ログインなし、日本語）。

| コンテナ | 役割 |
| --- | --- |
| `prometheus` | メトリクスを集める（`http://localhost:9090`） |
| `cadvisor` | コンテナごとの CPU・メモリと、その上限 |
| `pushgateway` | 定期処理（`wind:fetch`・`balloons:move`）が1回ごとに送る成否・かかった秒数 |
| `blackbox` | API の `/up` に応答があるか、応答時間 |
| `loki`・`alloy` | 全コンテナの標準出力のログ（3日分） |
| `grafana` | 管理画面。ダッシュボード「推し風 SRE」と、監視（アラートルール）の判定 |
| `monitor-sync` | 監視の一覧（`sre/grafana/monitors.py`）を Grafana に登録し、ON の監視のヘルスチェック先だけを Prometheus に渡し続ける |

- 各コンテナの CPU とメモリの上限は、`compose.yaml` と `sre/compose.yaml` の `deploy.resources.limits` に書いています
- アラートは通知せず、管理画面で見ます

### 監視の一覧

監視は「【対象】観点」の名前で、`sre/grafana/monitors.py` に書いています。管理画面の左のメニューの「アラート」→「アラートルール」で一覧を見られ、監視ごとに一時停止（OFF）できます。OFF にした監視は、`docker compose up` し直しても OFF のままです。API の死活・応答時間のように外から叩く監視は、OFF にすると15秒ほどで叩くのもやめます（`/up` は死活と応答時間の両方が OFF のときだけ止まります）。

| 対象 | 観点 | アラートになる条件 |
| --- | --- | --- |
| 推し風 API・風船同期バッチ・風データ取得バッチ・DB（PostgreSQL）・配信（Redis）・音声ストレージ（MinIO） | CPU使用率 | 上限の80%を超えて2分続く |
| 〃 | メモリ使用率 | 上限の90%を超えて2分続く（上限に達すると強制終了される） |
| 〃 | 稼働 | コンテナが1分以上見えない |
| 推し風 風船同期バッチ（`balloons:move`） | 成功の途絶 | 60秒以上成功していない |
| 〃 | 失敗 | 直近5分に1回でも失敗した |
| 〃 | 処理時間 | 1回が5秒の間隔を超えて1分続く |
| 推し風 風データ取得バッチ（`wind:fetch`） | 成功の途絶 | 5分以上成功していない |
| 〃 | 失敗 | 直近5分に1回でも失敗した |
| 推し風 API | 死活（/up） | ヘルスチェック（15秒ごと）が2回続けて失敗した |
| 〃 | 応答時間（/up） | `/up` の応答に1秒以上かかる状態が5分続く |
| 〃 | 死活（/up_broken・確認用） | 存在しないパスを叩くので、ON にすると約40秒で必ず発生する。アラートの出方を確かめるためのもので、普段は OFF |

Docker Desktop は containerd のイメージストアを使うため、cAdvisor からは compose のサービス名が見えません。そこで `cgroup_parent` でサービスごとに cgroup を `/fukyou/<サービス名>` に分け、その名前からサービスを見分けています。サービスを足したときは `cgroup_parent` も足してください。

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
| `balloons` | `balloons:move` | 保存済みの風データで、飛行中の風船を5秒ごとに動かし、`/ws` の `BalloonsChannel` へ `balloons.snapshot` を配信する。日本の排他的経済水域（EEZ）の外へ出た風船は割れる（`status` が `lost` になる）。港から10km以内に来た風船は船に乗り、太平洋側の港からは日本海側の港へ、日本海側の港からは太平洋側の港へ、風に関係なく1分で運ばれる |

- Open-Meteo の無料枠は地点の数で数え、1分に600、1時間に5,000、1日に10,000までです。20分ごとに100地点なら1日7,200で収まります
- 速度の倍率は `compose.yaml` の `SPEED_SCALE` で変えられます（変えたら `docker compose up -d` で作り直す）
- `wind_grid` には初期データとして、2026年11月7日の Open-Meteo の風（`backend/db/seeds/wind_grid.json`、CC BY 4.0）が入ります。DB を新しく作ると `db:prepare` で自動で入り、既存の DB には `docker compose exec app ruby bin/rails db:seed` で入れられます。初期データは日時を古くしてあるので、実際の予報を取得した地点から順に置き換わります
- どちらの定期処理も advisory lock で1プロセスだけが動きます。落ちたら compose が再起動します
- ログはエラーだけが出ます（`docker compose logs -f wind balloons`）。SQL などの詳しいログは `backend/log/development.log` にあります

届くデータは、`docs/websocket-viewer.html` をブラウザで開くと確かめられます。`/ws` に接続して `BalloonsChannel` を購読し、届いたメッセージの生データ、最新の snapshot の表、地図上の風船を表示します。

### 日本の排他的経済水域のデータ

`backend/config/japan_eez.json` は、[Marine Regions](https://www.marineregions.org/) の Maritime Boundaries and Exclusive Economic Zones（200NM）version 12（CC BY 4.0）から作りました。日本の EEZ に加え、北方領土・尖閣諸島・竹島周辺の主張の重なる海域と、日韓の共同開発区域を含みます。EEZ の形は陸地が穴になっているので外側の輪だけを使い（陸地も中に含める）、0.02度（約2 km）で間引いています。

### 船の航路のデータ

`backend/config/sea_routes.json` は、次の3つを持ちます。

- **港（229港）**：[国土数値情報（港湾間流通量・海上経路データ）](https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-S10a-v1_2.html)の平成28年度の海上経路（国土交通省、商用利用可）で、日本の港どうしの航路が出入りする港です（同じ座標で名前だけ違う博多と福岡は、博多だけ残しています）。北海道の西岸・新潟・佐渡・敦賀・舞鶴・玄界灘・対馬・壱岐の25港を日本海側、それ以外（瀬戸内・東シナ海・南西諸島を含む）を太平洋側としています
- **中継点（124点）**：日本を囲む海の上に手で置いた点です。津軽海峡・関門海峡・瀬戸内も通ります
- **つながり**：港と中継点のうち、[Natural Earth](https://www.naturalearthdata.com/)（パブリックドメイン）の1:10mの陸地を横切らない組です。この陸地の図では閉じてしまう関門海峡と友ヶ島水道は、手でつないでいます

船に乗ると、反対側の港をランダムに選び、つながりをたどる最短の道を進みます。

- 降りた港と、その港から10km以内の港では、次に別の港へ着くまで乗り直しません
- 風船を飛ばした場所から10km以内の港では乗りません
- 小さな島や細い水路は陸地の図にないので、道がかすめることがあります
