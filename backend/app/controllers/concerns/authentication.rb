# Authorization: Bearer <token> ヘッダーから本人を特定する。
# 全ての API で認証を求め、不要な API だけ allow_unauthenticated_access で外す
module Authentication
  extend ActiveSupport::Concern

  included do
    include ActionController::HttpAuthentication::Token::ControllerMethods

    before_action :authenticate!
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :authenticate!, **options
    end
  end

  private

  attr_reader :current_auth_token

  def current_user
    current_auth_token&.user
  end

  def authenticate!
    @current_auth_token = authenticate_with_http_token do |token, _options|
      AuthToken.find_by_token(token)
    end
    render_error(:unauthorized, code: "unauthorized", message: "ログインしてください") unless current_auth_token
  end
end
