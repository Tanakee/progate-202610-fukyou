module Me
  class JourneysController < ApplicationController
    def index
      @journeys = current_user.journeys.order(created_at: :desc)
    end
  end
end
