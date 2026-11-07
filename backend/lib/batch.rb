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

    loop do
      started_at = Time.current
      begin
        yield
      rescue => error
        Rails.logger.error("#{name}: #{error.class}: #{error.message}")
      end
      # 間隔を超えた回は遅れを取り戻そうとせず、次の区切りまで待つ
      sleep(every - (Time.current - started_at) % every)
    end
  end
end
