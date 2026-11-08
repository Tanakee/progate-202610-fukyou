require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Backend
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # 1日の区切り（回収は1日1回）を日本時間の0時にする。DBには UTC で保存する
    config.time_zone = "Asia/Tokyo"
    config.i18n.default_locale = :ja

    # デモの前に早送りするだけなので、設定用のテーブルは作らず環境変数で持つ
    config.x.speed_scale = ENV.fetch("SPEED_SCALE", "1").to_f

    config.action_cable.mount_path = "/ws"
    # 既定の5分にしないのは、アプリが曲の URL を覚えたまま、同じ曲を何度もループして流すから
    config.active_storage.service_urls_expire_in = 1.day
    # 接続元はブラウザではなく iOS アプリで、Origin ヘッダーが付かないため検査しない
    config.action_cable.disable_request_forgery_protection = true
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # routes の defaults format: :json で全リクエストに format が付き、permit のたびに警告が出るのを防ぐ
    config.action_controller.always_permitted_parameters = %w[controller action format]
  end
end
