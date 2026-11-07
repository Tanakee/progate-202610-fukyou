module Auth
  class SessionsController < ApplicationController
    allow_unauthenticated_access only: :create

    # POST /auth/login
    def create
      @user = User.authenticate_by_credentials(email: params[:email], password: params[:password])
      unless @user
        return render_error(:unauthorized, code: "invalid_credentials", message: "メールアドレスまたはパスワードが違います")
      end

      @token = AuthToken.issue!(@user)
      render "auth/token"
    end

    # DELETE /auth/session
    # 送られた token だけを無効にする。他の端末の token は残る
    def destroy
      current_auth_token.destroy!
      head :no_content
    end
  end
end
