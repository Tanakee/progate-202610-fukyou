module Auth
  class SignupsController < ApplicationController
    allow_unauthenticated_access
    # uniqueness の検証だけでは、同じメールアドレスの同時登録を防げない
    rescue_from ActiveRecord::RecordNotUnique, with: :render_email_taken

    def create
      @user = User.new(user_params)
      @auth_token = @user.auth_tokens.build

      if @user.save
        render :create, status: :created
      elsif @user.errors.of_kind?(:email, :taken)
        render_email_taken
      else
        render_error :unprocessable_content, code: "validation_failed", message: @user.errors.full_messages.first
      end
    end

    private
      def user_params
        params.permit(:email, :password)
      end

      def render_email_taken
        render_error :conflict, code: "email_taken", message: "このメールアドレスは登録済みです"
      end
  end
end
