# 動作検証用API

開発・テスト環境でのみ利用できます。本番環境にはルートを作成しません。
どちらもログイン時に取得したBearerトークンが必要です。

## 準備

DBの変更を適用してアプリを再起動します。

```powershell
docker compose exec app ruby bin/rails db:migrate
docker compose restart app
```

以下の `$token` にはログインAPIで取得したトークンを設定してください。

## お気に入り回収上限のリセット

```powershell
curl.exe -X POST "http://localhost:3000/test_reset_favorite_limit" -H "Authorization: Bearer $token"
```

成功時は `200 OK` と `{"reset_count":1}` を返します。
対象はログイン中のユーザーの日本時間で当日の回収です。
お気に入りと回収日は残し、対象の回収だけを1日1回の上限から除外します。
リセット後の回収は通常どおり上限を消費します。
対象がなければ `reset_count` は0です。

## 飛行中の風船の再配置

```powershell
curl.exe -X POST "http://localhost:3000/test_reposition_balloons" -H "Authorization: Bearer $token"
```

成功時は `200 OK` と `{"updated_count":2}` のような更新件数を返します。
全ユーザーの `flying` の風船を、47都道府県の県庁所在地から風船ごとにランダムに選んだ地点へ配置します。
東京都の候補は都庁所在地の新宿区です。同じ地点に複数の風船が配置される場合があります。
新しい風船は作成しません。
回収済み・消失済みの風船や、出発位置・出発時刻は変更しません。

速度を0にし、移動時刻を現在に合わせて航路の状態を解除した後、
`BalloonsChannel` に更新後のsnapshotを配信します。
配置後は通常の定期移動が再開します。位置を固定するAPIではありません。

## エラー

- 未認証: `401 Unauthorized`
- 本番環境: `404 Not Found`

## テスト

```powershell
docker compose exec app ruby bin/rails test test/integration/test_tools_test.rb test/integration/collections_test.rb test/models/balloon_test.rb
```
