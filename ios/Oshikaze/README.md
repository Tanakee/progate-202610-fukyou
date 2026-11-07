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

実機からつなぐときは、`compose.yaml` の `app` の `ports` を `"3000:3000"` にし、`Config/Local.xcconfig` の `API_BASE_URL` をMacのアドレスにします。IPv6のアドレスは `[]` で囲みます。

```
API_BASE_URL = http:/$()/[240b:...]:3000
```

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
