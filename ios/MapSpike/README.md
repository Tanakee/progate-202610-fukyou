## 3D地図の試作アプリ

MapKitの3D地図に風船を載せ、見た目と動きを確かめるための試作です（#13）。本番のアプリとは別物です。

風船の位置は、上部の切り替えで2通りから選べます。

- **端末で計算**: アプリがOpen-Meteoから日本周辺168地点の風を取り、30個の風船を動かす。BEなしで動く
- **BEの配信**: BEの `/ws`（`BalloonsChannel`）から `balloons.snapshot` を受け取り、5秒の間を `ve` / `vn` × `speed_scale` で補間する。本番と同じ方式

### 準備

```sh
cd ios/MapSpike
cp Config/Local.xcconfig.example Config/Local.xcconfig   # DEVELOPMENT_TEAM を自分のTeam IDにする
xcodegen generate
open MapSpike.xcodeproj
```

### BEにつなぐ

リポジトリ直下で `docker compose up` を実行します。シミュレーターなら初期値の `ws://localhost:3000/ws` のままつながります。

実機からつなぐには、`compose.yaml` の `app` の `ports` を `"3000:3000"` にして、Mac以外からも接続できるようにします。学校や会社のWi-Fiは端末同士の通信を禁止していることがあるので、iPhoneのテザリングにMacをつなぐと確実です。

```sh
xcrun devicectl device process launch --device <デバイスID> com.tanakee.oshikaze.mapspike \
  -- -source server -serverURL "ws://[MacのIPv6アドレス]:3000/ws"
```

風船は、ボット風船を入れるまでは飛んでいません。
