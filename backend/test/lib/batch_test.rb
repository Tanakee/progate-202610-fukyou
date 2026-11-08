require "test_helper"

class BatchTest < ActiveSupport::TestCase
  test "1回ごとに、結果ごとの回数と最後の時刻・かかった秒数を Pushgateway へ送る" do
    request = capture_request do |url|
      with_pushgateway(url) do
        Batch.report("balloons:move", result: "failure", runs: { "success" => 3, "failure" => 1 }, duration: 0.25, now: Time.at(1_800_000_000))
      end
    end

    assert_match %r{\APOST /metrics/job/batch/batch/balloons:move }, request
    assert_includes request, %(batch_runs_total{result="success"} 3\nbatch_runs_total{result="failure"} 1\n)
    assert_includes request, "batch_last_failure_timestamp_seconds 1800000000.0\n"
    assert_includes request, "batch_last_duration_seconds 0.25\n"
  end

  test "Pushgateway に届かなくても、例外を出さない" do
    with_pushgateway("http://127.0.0.1:1") do
      assert_nothing_raised do
        Batch.report("wind:fetch", result: "success", runs: { "success" => 1, "failure" => 0 }, duration: 0.1)
      end
    end
  end

  private
    def capture_request
      server = TCPServer.new("127.0.0.1", 0)
      reader = Thread.new do
        client = server.accept
        head = client.gets("\r\n\r\n")
        body = client.read(head[/Content-Length: (\d+)/i, 1].to_i)
        client.write("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
        client.close
        head + body
      end
      yield "http://127.0.0.1:#{server.addr[1]}"
      reader.join(5)&.value
    ensure
      server&.close
    end

    def with_pushgateway(url)
      previous, ENV["PUSHGATEWAY_URL"] = ENV["PUSHGATEWAY_URL"], url
      yield
    ensure
      ENV["PUSHGATEWAY_URL"] = previous
    end
end
