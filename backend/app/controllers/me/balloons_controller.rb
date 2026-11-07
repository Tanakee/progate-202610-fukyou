module Me
  class BalloonsController < ApplicationController
    def index
      @balloons = current_user.balloons.flying
    end
  end
end
