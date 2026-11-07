module Me
  class PopsController < ApplicationController
    def index
      @balloon_ids = current_user.pops.order(popped_at: :desc).pluck(:balloon_id)
    end
  end
end
