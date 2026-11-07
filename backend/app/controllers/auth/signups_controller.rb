module Auth
  class SignupsController < ApplicationController
    allow_unauthenticated_access

    # POST /auth/signup
    def create
      @user = User.new(signup_params)

      ActiveRecord::Base.transaction do
        @user.save!
        @token = AuthToken.issue!(@user)
      end
      render "auth/token", status: :created
    rescue ActiveRecord::RecordInvalid
      render_signup_error
    rescue ActiveRecord::RecordNotUnique
      # 同じメールアドレスで同時に登録された場合
      render_email_taken
    end

    private

    def signup_params
      params.permit(:email, :password)
    end

    def render_signup_error
      return render_email_taken if @user.errors.of_kind?(:email, :taken)

      render_error(:unprocessable_content, code: "validation_failed", message: @user.errors.full_messages.first)
    end

    def render_email_taken
      render_error(:conflict, code: "email_taken", message: "このメールアドレスは登録済みです")
    end
  end
end
