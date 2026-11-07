namespace :ticker do
  desc "風データを3時間ごとに取得し、風船の位置を5秒ごとに計算して配信する"
  task run: :environment do
    # コンテナのログに即座に出すため、標準出力をバッファしない
    $stdout.sync = true
    Rails.logger.broadcast_to(ActiveSupport::Logger.new($stdout))

    # 2つ目の定期処理を起動しても位置を二重に進めないよう、ロックを取れたプロセスだけが動く。
    # with_connection だと接続がプールへ戻ってロックの持ち主が変わりうるので、接続を借りたままにする
    until ActiveRecord::Base.lease_connection.select_value("SELECT pg_try_advisory_lock(#{Zlib.crc32('ticker')})")
      sleep 5
    end

    wind_batch = 0
    next_wind_fetch_at =
      if WindGrid.at(Time.current).size < WindGrid::POINTS.size
        Time.current
      else
        WindGrid.maximum(:fetched_at) + WindGrid::FETCH_INTERVAL
      end

    loop do
      started_at = Time.current
      begin
        if started_at >= next_wind_fetch_at
          points = WindGrid::BATCHES[wind_batch]
          wind_batch = (wind_batch + 1) % WindGrid::BATCHES.size
          # 取得の前に次の予定を決め、失敗しても Open-Meteo へ5秒ごとに問い合わせ続けないようにする
          next_wind_fetch_at = started_at + (wind_batch.zero? ? WindGrid::FETCH_INTERVAL : 1.minute)
          WindGrid.fetch!(points)
        end
        Balloon.move_flying!(wind: WindGrid.at(started_at), speed_scale: Rails.configuration.x.speed_scale)
        BalloonsChannel.broadcast_snapshot
      rescue => error
        Rails.logger.error("ticker: #{error.class}: #{error.message}")
      end
      # 5秒を超えた回は遅れを取り戻そうとせず、次の5秒の区切りまで待つ
      sleep(5 - (Time.current - started_at) % 5)
    end
  end
end
