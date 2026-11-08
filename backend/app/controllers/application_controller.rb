class ApplicationController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods
  # テストで使う Disk のサービスは、URL を作るのにリクエストのホスト名が要る
  include ActiveStorage::SetCurrent

  before_action :authenticate

  rescue_from ActiveRecord::RecordNotFound do
    render_error :not_found, code: "not_found", message: "見つかりません"
  end

  # アプリは平たい JSON を送る。モデル名のキーで包むと、permit のたびに不要なキーが混ざるので包まない
  wrap_parameters false

  private
    attr_reader :current_auth_token

    def current_user
      current_auth_token.user
    end

    def authenticate
      @current_auth_token = authenticate_with_http_token { |token| AuthToken.find_by_token(token) }
      render_error :unauthorized, code: "unauthorized", message: "ログインしてください" unless current_auth_token
    end

    def render_error(status, code:, message:)
      render "errors/show", status: status, locals: { code: code, message: message }
    end
end
