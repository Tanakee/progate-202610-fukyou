class MeController < ApplicationController
  def show
    @user = Current.user
  end
end
