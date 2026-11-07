module Authentication
  extend ActiveSupport::Concern

  included do
    include ActionController::HttpAuthentication::Token::ControllerMethods

    before_action :require_authentication
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def require_authentication
      resume_auth_token || request_authentication
    end

    def resume_auth_token
      Current.auth_token ||= authenticate_with_http_token do |token, _options|
        AuthToken.find_by_token(token)
      end
    end

    def request_authentication
      render_error :unauthorized, code: "unauthorized", message: "ログインしてください"
    end
end
