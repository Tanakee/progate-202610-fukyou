class ApplicationController < ActionController::API
  include Authentication

  # リクエストの JSON はキーをそのまま受け取る（コントローラー名のキーで包まない）
  wrap_parameters false

  private

  # エラーは全て { code, message } の形で返す
  def render_error(status, code:, message:)
    render "errors/error", status: status, locals: { code: code, message: message }
  end
end
