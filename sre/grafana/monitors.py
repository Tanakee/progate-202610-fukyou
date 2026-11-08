"""監視（Grafana のアラートルール）の一覧と、Grafana への登録、ヘルスチェック先の書き出し。

monitor-sync コンテナが起動時にこの一覧どおりにルールを作り直し、そのあとは動き続けて、
ON の監視が使うヘルスチェック先だけを Prometheus の読むファイルに書き出す（OFF の監視の先は叩かない）。
管理画面で一時停止（OFF）したルールは、OFF のまま残す。

ファイルから読み込ませる（provisioning）のではなく API で登録するのは、ファイルから読み込んだルールは
管理画面で一時停止できず、監視の ON/OFF を画面から切り替えられないから。
"""
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request

GRAFANA = "http://grafana:3000"
PROBE_TARGETS = "/prometheus-targets/api.json"
SYNC_SECONDS = 15
FOLDER = {"uid": "oshikaze-monitors", "title": "推し風 監視"}

SERVICES = {
    "app": "推し風 API",
    "balloons": "推し風 風船同期バッチ",
    "wind": "推し風 風データ取得バッチ",
    "db": "推し風 DB（PostgreSQL）",
    "redis": "推し風 配信（Redis）",
    "minio": "推し風 音声ストレージ（MinIO）",
}
BATCHES = {"balloons": "balloons:move", "wind": "wind:fetch"}


def monitor(uid, service, aspect, expr, op, threshold, for_, severity, summary, no_data="OK", paused=False, probe=None):
    return {
        "uid": uid, "group": SERVICES[service], "title": f"【{SERVICES[service]}】{aspect}",
        "expr": expr, "op": op, "threshold": threshold, "for": for_, "no_data": no_data,
        "severity": severity, "summary": summary, "paused": paused, "probe": probe,
    }


MONITORS = []
for service, name in SERVICES.items():
    MONITORS += [
        monitor(f"{service}-cpu", service, "CPU使用率",
                f'sum(rate(container_cpu_usage_seconds_total{{service="{service}"}}[1m]))'
                f' / max(container_spec_cpu_quota{{service="{service}"}} / container_spec_cpu_period{{service="{service}"}})',
                "gt", 0.8, "2m", "warning", f"{name} の CPU が上限の80%を超えています。5秒ごとの処理が間に合わなくなります"),
        monitor(f"{service}-memory", service, "メモリ使用率",
                f'max(container_memory_working_set_bytes{{service="{service}"}}) / max(container_spec_memory_limit_bytes{{service="{service}"}})',
                "gt", 0.9, "2m", "critical", f"{name} のメモリが上限の90%を超えています。上限に達すると強制終了されます"),
        # 止まったコンテナの系列は5分残るので、値がないときだけでなく、最後に見えた時刻でも判定する
        monitor(f"{service}-alive", service, "稼働",
                f'time() - max(container_last_seen{{service="{service}"}})',
                "gt", 60, "1m", "critical", f"{name} のコンテナが1分以上動いていません", no_data="Alerting"),
    ]

for service, batch in BATCHES.items():
    MONITORS += [
        monitor(f"{service}-batch-stalled", service, "成功の途絶",
                f'time() - batch_last_success_timestamp_seconds{{batch="{batch}"}}',
                "gt", 60 if service == "balloons" else 300, "0s", "critical",
                f"{batch} が {'60秒' if service == 'balloons' else '5分'} 以上成功していません", no_data="Alerting"),
        monitor(f"{service}-batch-failing", service, "失敗",
                f'increase(batch_runs_total{{batch="{batch}",result="failure"}}[5m])',
                "gt", 0, "0s", "warning", f"{batch} が直近5分に失敗しました。ログを確認してください"),
    ]
MONITORS.append(
    monitor("balloons-batch-overrunning", "balloons", "処理時間",
            'batch_last_duration_seconds{batch="balloons:move"}',
            "gt", 5, "1m", "warning", "balloons:move の1回が5秒の間隔に収まらず、風船の動きが飛び飛びになります"))

MONITORS += [
    monitor("app-up", "app", "死活（/up）", 'probe_success{job="api",instance="http://app:3000/up"}',
            "lt", 1, "1m", "critical", "API の /up に応答がありません", no_data="Alerting", probe="http://app:3000/up"),
    monitor("app-latency", "app", "応答時間（/up）", 'probe_duration_seconds{job="api",instance="http://app:3000/up"}',
            "gt", 1, "5m", "warning", "API の /up の応答に1秒以上かかっています", probe="http://app:3000/up"),
    # わざと存在しないパスを叩く、アラートの出方を確かめるための監視。普段は OFF にしておく
    monitor("app-up-broken", "app", "死活（/up_broken・確認用）", 'probe_success{job="api",instance="http://app:3000/up_broken"}',
            "lt", 1, "1m", "critical", "確認用の監視です。存在しないパス /up_broken を叩いているので、ON にすると必ず発生します",
            no_data="Alerting", paused=True, probe="http://app:3000/up_broken"),
]


def request(method, path, body=None):
    headers = {"Content-Type": "application/json", "X-Disable-Provenance": "true"}
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(GRAFANA + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as res:
            return json.load(res) if res.length != 0 else None
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise RuntimeError(f"{method} {path}: {error.code} {error.read().decode()}") from error


def rule(m, paused):
    return {
        "uid": m["uid"], "title": m["title"], "folderUID": FOLDER["uid"], "ruleGroup": m["group"], "orgID": 1,
        "condition": "B",
        "data": [
            {"refId": "A", "datasourceUid": "prometheus", "relativeTimeRange": {"from": 600, "to": 0},
             "model": {"refId": "A", "expr": m["expr"], "instant": True}},
            {"refId": "B", "datasourceUid": "__expr__",
             "model": {"refId": "B", "type": "threshold", "expression": "A",
                       "conditions": [{"evaluator": {"type": m["op"], "params": [m["threshold"]]}}]}},
        ],
        "for": m["for"], "noDataState": m["no_data"], "execErrState": "Error",
        "labels": {"severity": m["severity"]}, "annotations": {"summary": m["summary"]},
        "isPaused": paused,
    }


def write_probe_targets():
    paused = {r["uid"]: r["isPaused"] for r in request("GET", "/api/v1/provisioning/alert-rules")}
    # 同じ先を2つの監視（/up の死活と応答時間）が使うので、どちらかが ON なら叩く
    targets = sorted({m["probe"] for m in MONITORS if m["probe"] and not paused.get(m["uid"], m["paused"])})
    # 書きかけを Prometheus に読まれないよう、別名で書いてから置き換える
    with open(PROBE_TARGETS + ".tmp", "w") as file:
        json.dump([{"targets": targets, "labels": {}}], file)
    os.replace(PROBE_TARGETS + ".tmp", PROBE_TARGETS)
    return targets


def wait_for_grafana():
    while True:
        try:
            if request("GET", "/api/health"):
                return
        except (urllib.error.URLError, RuntimeError):
            pass
        time.sleep(2)


def main():
    wait_for_grafana()

    if not request("GET", f"/api/folders/{FOLDER['uid']}"):
        request("POST", "/api/folders", FOLDER)

    for m in MONITORS:
        existing = request("GET", f"/api/v1/provisioning/alert-rules/{m['uid']}")
        paused = existing["isPaused"] if existing else m["paused"]
        if existing:
            request("PUT", f"/api/v1/provisioning/alert-rules/{m['uid']}", rule(m, paused))
        else:
            request("POST", "/api/v1/provisioning/alert-rules", rule(m, paused))
        print(("OFF " if paused else "ON  ") + m["title"])

    for group in dict.fromkeys(m["group"] for m in MONITORS):
        path = f"/api/v1/provisioning/folder/{FOLDER['uid']}/rule-groups/{urllib.parse.quote(group)}"
        current = request("GET", path)
        current["interval"] = 10
        request("PUT", path, current)

    written = None
    while True:
        try:
            targets = write_probe_targets()
            if targets != written:
                print("ヘルスチェック先: " + ", ".join(targets or ["なし"]), flush=True)
                written = targets
        except (urllib.error.URLError, RuntimeError) as error:
            # Grafana が再起動している間は、前に書いたヘルスチェック先のまま待つ
            print(f"ヘルスチェック先を更新できませんでした: {error}", flush=True)
        time.sleep(SYNC_SECONDS)


if __name__ == "__main__":
    main()
