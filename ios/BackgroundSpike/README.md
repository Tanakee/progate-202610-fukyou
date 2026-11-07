## バックグラウンド動作の検証アプリ

設計書の「1日目の検証」を実機で確かめるための、画面1枚のアプリです（#9）。本番のアプリとは別物で、検証が終わったら消してかまいません。

### 準備

```sh
cd ios/BackgroundSpike
cp Config/Local.xcconfig.example Config/Local.xcconfig   # DEVELOPMENT_TEAM を自分のTeam IDにする
xcodegen generate
open BackgroundSpike.xcodeproj
```

- Team IDは Xcode の Settings > Accounts で確認できます。無料アカウントでもかまいません
- 他の人と同じBundle IDが使えない場合は、`Local.xcconfig` で `PRODUCT_BUNDLE_IDENTIFIER` を変えます
- iPhoneを接続して実行し、初回は iPhone の「設定 > 一般 > VPNとデバイス管理」で開発元を信頼します

### 検証用サーバーの起動

MacとiPhoneを同じWi-Fiにつなぎ、次を実行します。依存パッケージは不要です。

```sh
node ios/BackgroundSpike/server/server.mjs
```

表示された `ws://192.168.x.x:8080` をアプリに入力して「接続する」を押します。初回はローカルネットワークへのアクセス許可を求められるので許可します。

サーバーは5秒ごとに連番を送り、30秒ごとに通知の合図を付けます。`n` を入力してEnterを押すと、すぐに合図を送ります。

学校や会社のWi-Fiでは端末同士の通信が禁止されていることがあり、その場合はタイムアウトします。iPhoneのテザリングにMacをつなぐと確実です。テザリングがIPv6だけのネットワークになる場合は、`ifconfig en0` で出るIPv6アドレスを `ws://[240b:...]:8080` の形で使います。

### Macから起動する

iPhoneをUSBでつないでいれば、ボタンを押さずに接続と再生まで始められます。手作業はロックだけになります。`-autoMode` を省くと再生せずに接続だけします。

```sh
xcrun devicectl device process launch --device <デバイスID> com.tanakee.oshikaze.backgroundspike \
  -- -autoURL ws://192.168.x.x:8080 -autoMode tracks   # tracks または silence
```

ログは次で取り出せます。

```sh
xcrun devicectl device copy from --device <デバイスID> --domain-type appDataContainer \
  --domain-identifier com.tanakee.oshikaze.backgroundspike \
  --source Documents/spike-log.txt --destination spike-log.txt
```

### 確かめ方

先にアプリで「通知を許可する」を押しておきます。ログは画面とファイルの両方に残るので、ロックを解除してから時刻と間隔を確認します。受信の間隔が7秒を超えると ⚠️ が付きます。

| # | 項目 | 手順 | 合格の条件 |
| --- | --- | --- | --- |
| 1 | 次の曲への連続再生 | 「2曲を連続再生」を押してロックする。1曲は20秒 | 40秒後も音が続き、ログに `曲の終了: track1` と `同じ曲をループ: track2` が残る |
| 2 | 再生中のWebSocket受信 | 接続してから再生し、ロックして3分待つ | ⚠️ のない `受信` が5秒ごとに並んでいる |
| 3 | 受信をきっかけにした通知 | #2 の状態のまま待つ | ロック画面に30秒ごとに通知が出る |
| 4 | 無音ループで5分 | 接続して「無音ループ」を押し、ロックして5分待つ | 5分間、⚠️ のない `受信` が並び、通知も出ている |
| 5 | 曲の終了、イヤホン、着信 | イヤホンを抜いて30秒後にロック画面から再開する。別の電話から着信させる | `イヤホンが外れた` `ロック画面から再開` `中断の開始` `中断の終了` が残り、再生が戻る |
| 6 | 無料アカウントでのビルド | 無料アカウントのTeamで実機に入れる | ビルドでき、Background Modes（Audio）が効いている（#1が通る） |
| 7 | 台数 | デモに使う全端末に入れる | 全台で起動する |
| 8 | 本番のAction Cable | BEのデプロイ後に確認する | — |

比較のため、再生せずに接続だけしてロックすると、数秒で受信が止まるはずです。止まらない場合は、検証の結果を疑ってください。

ログは右上の共有ボタンからファイルで書き出せます。結果は #9 に記録します。
