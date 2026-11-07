module Auth
  class SignupsController < ApplicationController
    skip_before_action :authenticate

    def create
      @user = User.new(params.permit(:email, :password))
      @auth_token = @user.auth_tokens.build

      if @user.save
        render :create, status: :created
      elsif @user.errors.of_kind?(:email, :taken)
        render_error :conflict, code: "email_taken", message: "このメールアドレスは登録済みです"
      else
        render_error :unprocessable_content, code: "validation_failed", message: @user.errors.full_messages.first
      end
    end
  end
end
