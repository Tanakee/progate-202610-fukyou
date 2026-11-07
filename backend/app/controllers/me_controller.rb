class MeController < ApplicationController
  # GET /me
  def show
    @user = current_user
    render "users/show"
  end
end
