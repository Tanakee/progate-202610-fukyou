require "net/http"

class Batch
  def self.run(name, every:)
    # バッファすると docker compose logs に出るのが遅れる。debug の SQL まで出すとエラーが埋もれるので info 以上だけ出す
    $stdout.sync = true
    Rails.logger.broadcast_to(ActiveSupport::Logger.new($stdout, level: :info)) unless Rails.env.production?

    # 同じバッチを2つ起動しても二重に動かないよう、ロックを取れたプロセスだけが動く。
    # with_connection だと接続がプールへ戻ってロックの持ち主が変わりうるので、接続を借りたままにする
    until ActiveRecord::Base.lease_connection.select_value("SELECT pg_try_advisory_lock(#{Zlib.crc32(name)})")
      sleep every
    end

    runs = { "success" => 0, "failure" => 0 }
    loop do
      started_at = Time.current
      result = begin
        yield
        "success"
      rescue => error
        Rails.logger.error("#{name}: #{error.class}: #{error.message}")
        "failure"
      end
      runs[result] += 1
      report(name, result:, runs:, duration: Time.current - started_at) if ENV["PUSHGATEWAY_URL"]
      # 間隔を超えた回は遅れを取り戻そうとせず、次の区切りまで待つ
      sleep(every - (Time.current - started_at) % every)
    end
  end

  # Prometheus から読みに来てもらわず Pushgateway へ送るのは、定期処理には読みに来てもらう HTTP の口がないから。
  # PUT ではなく POST にするのは、成功の時刻を送った後に失敗の時刻を送っても、成功の時刻を消さないため
  def self.report(name, result:, runs:, duration:, now: Time.current)
    body = <<~METRICS
      # TYPE batch_runs_total counter
      #{runs.map { |key, count| %(batch_runs_total{result="#{key}"} #{count}) }.join("\n")}
      # TYPE batch_last_#{result}_timestamp_seconds gauge
      batch_last_#{result}_timestamp_seconds #{now.to_f}
      # TYPE batch_last_duration_seconds gauge
      batch_last_duration_seconds #{duration.to_f}
    METRICS

    uri = URI("#{ENV.fetch('PUSHGATEWAY_URL')}/metrics/job/batch/batch/#{name}")
    # 既定の60秒待たないのは、Pushgateway が止まっている間、5秒ごとの定期処理まで止まってしまうから
    Net::HTTP.start(uri.host, uri.port, open_timeout: 1, read_timeout: 1) { _1.post(uri.path, body) }
  rescue => error
    # 監視のための送信に失敗しても、定期処理は止めない
    Rails.logger.warn("#{name}: メトリクスを送れませんでした: #{error.class}: #{error.message}")
  end
end
