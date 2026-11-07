module Auth
  class SessionsController < ApplicationController
    skip_before_action :authenticate, only: :create
    rate_limit to: 10, within: 3.minutes, only: :create, with: -> {
      render_error :too_many_requests, code: "too_many_requests", message: "しばらくしてからもう一度お試しください"
    }

    def create
      if user = User.authenticate_by(params.permit(:email, :password))
        @auth_token = user.auth_tokens.create!
      else
        render_error :unauthorized, code: "invalid_credentials", message: "メールアドレスまたはパスワードが違います"
      end
    end

    # 他の端末でのログインまで切らないよう、送られてきた token だけを消す
    def destroy
      current_auth_token.destroy!
      head :no_content
    end
  end
end
