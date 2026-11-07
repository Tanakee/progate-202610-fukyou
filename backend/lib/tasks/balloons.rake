namespace :balloons do
  desc "保存済みの風データで飛行中の風船を5秒ごとに動かし、全員向けに配信する"
  task move: :environment do
    Batch.run("balloons:move", every: 5.seconds) do
      Balloon.move_flying!(wind: WindGrid.at(Time.current), speed_scale: Rails.configuration.x.speed_scale)
      BalloonsChannel.broadcast_snapshot
    end
  end
end
