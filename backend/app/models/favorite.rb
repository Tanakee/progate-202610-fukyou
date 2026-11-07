class Favorite < ApplicationRecord
  belongs_to :user
  belongs_to :balloon
  has_one :track, through: :balloon
end
