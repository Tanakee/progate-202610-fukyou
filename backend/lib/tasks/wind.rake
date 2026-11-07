namespace :wind do
  desc "Open-Meteo から、いちばん古い格子点の風データを100地点ずつ取得し続ける"
  task fetch: :environment do
    Batch.run("wind:fetch", every: 1.minute) do
      WindGrid.fetch!(WindGrid.stalest_points) if WindGrid.fetch_due?
    end
  end
end
