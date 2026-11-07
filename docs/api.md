# API一覧

推し風のBEが提供するAPIの一覧です。REST APIは15本、WebSocketイベントは4種類です。
設計の背景は `design-document.pdf` を、処理の流れは `diagrams/index.html` を参照してください。
リクエストとレスポンスの詳しい形は `backend/openapi/swagger.yml`、テーブルの定義は `diagrams/erd-data-model-20261102-100000/data-model.html` を参照してください。

認証が「必要」なAPIは、ログインまたは新規登録で返る `token` を `Authorization: Bearer <token>` ヘッダーで送ります。サーバーはこの `token` から本人を特定するので、パスやボディに利用者IDは入れません。

## REST API

### 認証と利用者

| メソッド | パス | 認証 | 成功 | 用途 | 主な入力 |
| --- | --- | --- | --- | --- | --- |
| POST | `/auth/signup` | 不要 | 201 | 新規登録 | メール、パスワード |
| POST | `/auth/login` | 不要 | 200 | ログイン | メール、パスワード |
| DELETE | `/auth/session` | 必要 | 204 | ログアウト | なし |
| GET | `/me` | 必要 | 200 | ログイン中の利用者を返す | なし |

### 曲

| メソッド | パス | 認証 | 成功 | 用途 | 主な入力 |
| --- | --- | --- | --- | --- | --- |
| POST | `/tracks` | 必要 | 201 | 曲をアップロードする | mp3、曲名、アーティスト名 |
| GET | `/tracks/:id` | 不要 | 200 | 曲名、アーティスト名、mp3のURLを返す | 曲ID |
| GET | `/me/tracks` | 必要 | 200 | 自分がアップロードした曲の一覧を返す | なし |

### 風船

| メソッド | パス | 認証 | 成功 | 用途 | 主な入力 |
| --- | --- | --- | --- | --- | --- |
| POST | `/balloons` | 必要 | 201 | 風船を飛ばす | 自分の曲ID、ぼかした出発地点、地名 |
| GET | `/me/balloons` | 必要 | 200 | 飛行中の自分の風船と回数を返す | なし |
| POST | `/balloons/:id/plays` | 必要 | 200 | 5秒再生されたら回数を加算する（1人1回） | 風船ID |
| POST | `/balloons/:id/collect` | 必要 | 200 | 回収する（1日1回） | 風船ID |
| POST | `/balloons/:id/pop` | 必要 | 200 | 割る（自分の世界からのみ消す） | 風船ID |

### マイページ

| メソッド | パス | 認証 | 成功 | 用途 | 主な入力 |
| --- | --- | --- | --- | --- | --- |
| GET | `/me/popped` | 必要 | 200 | 割った風船のID一覧を返す | なし |
| GET | `/me/favorites` | 必要 | 200 | お気に入り一覧を返す | なし |
| GET | `/me/journeys` | 必要 | 200 | 旅の記録カード一覧を返す | なし |

## エラーと再送時の応答

エラーは `{code, message}` の形で返します。

| API | 応答 | 条件 |
| --- | --- | --- |
| 認証が必要なAPI | 401 | トークンがない、または無効 |
| `POST /auth/signup` | 409 | メールアドレスが登録済み（大文字と小文字は区別しない） |
| `POST /auth/signup` | 422 | メールアドレスの形式が正しくない、またはパスワードが8〜128文字ではない |
| `POST /auth/login` | 401 | メールアドレスまたはパスワードが違う |
| `POST /auth/login` | 429 | 同じ接続元から3分間に10回を超えてログインを試みた |
| `POST /tracks` | 422 | mp3ではない、または20MBを超えている |
| `POST /balloons` | 403 | 他の人の曲を飛ばそうとした |
| `POST /balloons` | 409 | 飛行中の風船がある。アプリは `/me/balloons` を読み直す |
| `POST /balloons` | 422 | 出発地点が対象範囲の外にある |
| `POST /balloons/:id/plays` | 200 | 再送や終了済みの風船でも成功とし、回数は増やさない |
| `POST /balloons/:id/collect` | 200 | 回収済みの本人が再送した |
| `POST /balloons/:id/collect` | 403 | 自分の風船を回収しようとした |
| `POST /balloons/:id/collect` | 409 | 飛行中ではない。先着に負けた場合も含み、回収回数は消費しない |
| `POST /balloons/:id/collect` | 429 | 今日すでに回収している。1日の区切りは日本時間の0時 |
| `POST /balloons/:id/pop` | 200 | 再送しても成功とする |

## WebSocket `/ws`

Action Cableで提供する、サーバーから端末への配信専用の接続です。配信には Redis を使い、風船を動かす定期処理のコンテナ（`balloons`）から全端末へ届けます。接続は匿名で許可し、全員向けのチャンネルと、トークンが必要な本人用チャンネルに分けます。ログイン後とログアウト後は再接続します。

| イベント | チャンネル | 届く相手 | タイミング |
| --- | --- | --- | --- |
| `balloons.snapshot` | 全員向け | 全員 | 接続時と5秒ごと |
| `balloon.removed` | 全員向け | 全員 | 回収された、または海や国外へ出たとき |
| `balloon.collected` | 本人用 | 飛ばした人 | 自分の風船が回収されたとき |
| `balloon.ended` | 本人用 | 飛ばした人 | 旅が終わり、記録カードができたとき |

### `balloons.snapshot` の形式

```json
{
  "event": "balloons.snapshot",
  "seq": 1794016905242,
  "server_time": "...",
  "speed_scale": 1,
  "balloons": [
    { "id": 1, "track_id": 7, "lat": 34.7, "lng": 135.5, "ve": 2.12, "vn": -4.01 }
  ]
}
```

全員向けチャンネルは `BalloonsChannel` です（`{"command":"subscribe","identifier":"{\"channel\":\"BalloonsChannel\"}"}` で購読）。同じチャンネルに複数のイベントを流すため、`event` で種類を見分けます。`seq` は送った時刻のミリ秒で、大きいほど新しい配信です。`ve` / `vn` は東向き・北向きの風の速さ（m/s、`speed_scale` を掛ける前）です。

`balloons.snapshot` が地図の状態の正で、新しい風船も次の配信で届きます。飛ばした人（`user_id`）は載せません。
