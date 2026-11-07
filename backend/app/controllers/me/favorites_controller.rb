module Me
  class FavoritesController < ApplicationController
    def index
      @favorites = current_user.favorites.includes(:track).order(created_at: :desc)
    end
  end
end
