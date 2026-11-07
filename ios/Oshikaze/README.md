## 推し風 iOSアプリ

### 準備

```sh
cd ios/Oshikaze
cp Config/Local.xcconfig.example Config/Local.xcconfig   # DEVELOPMENT_TEAM を自分のTeam IDにする
xcodegen generate
open Oshikaze.xcodeproj
```

プロジェクトは XcodeGen で生成するので、`Oshikaze.xcodeproj` はコミットしません。ファイルを足したら `xcodegen generate` をやり直します。

### BEにつなぐ

リポジトリ直下で `docker compose up` を実行します。シミュレーターなら、初期値の `http://localhost:3000` のままつながります。

実機から手元のBEにつなぐときは、ngrok などで公開URLを付けるのが確実です。学校や会場のWi-Fiは端末同士の通信を禁止していることが多く、テザリングでも親機のiPhoneから子機のMacへの通信は安定しませんでした。

```sh
ngrok http 3000
```

Railsは知らないホスト名からのアクセスを弾くので、`compose.yaml`（または手元だけの `compose.override.yaml`）の `app` に `RAILS_DEVELOPMENT_HOSTS: ".ngrok-free.dev"` を足します。

接続先は、ビルドし直さずに起動引数で切り替えられます。一度渡すとiPhoneに保存され、次の起動からも使います。元に戻すには、別の値を渡すか、アプリを入れ直します。

```sh
xcrun devicectl device process launch --device <デバイスID> com.tanakee.oshikaze \
  -- -apiBaseURL https://xxxx.ngrok-free.dev
```

ビルドの設定で決めるときは、`Config/Local.xcconfig` の `API_BASE_URL` を書き換えます。

### シミュレーターで現在地を決める

```sh
xcrun simctl location booted set 35.68,139.77   # 東京駅
```

### テスト

```sh
xcodebuild -project Oshikaze.xcodeproj -scheme Oshikaze -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

### 構成

| フォルダ | 内容 |
| --- | --- |
| `App` | 起動、接続先の設定（`API_BASE_URL`） |
| `Balloons` | `/ws` の購読（`BalloonFeed`）。`balloons.snapshot` を正とし、次の配信までは `ve` / `vn` × `speed_scale` で補間する |
| `Location` | 使用中のみの許可で現在地を取る。サーバーへは送らない |
| `Playback` | 流す風船の判定（30秒に1回、1割以上近いときだけ乗り換える）、フェードでの切り替え、無音ループ |
| `Screens` | 3D地図と再生バー |

`GET /tracks/:id` ができるまでは、曲名と音源は `TrackCatalog` の仮のものを使います。
