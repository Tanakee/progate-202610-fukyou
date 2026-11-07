class ApplicationController < ActionController::API
  include Authentication

  # アプリは平たい JSON を送る。モデル名のキーで包むと、permit のたびに不要なキーが混ざるので包まない
  wrap_parameters false

  private
    def render_error(status, code:, message:)
      render "errors/show", status: status, locals: { code: code, message: message }
    end
end
