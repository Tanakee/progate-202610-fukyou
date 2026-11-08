class Track < ApplicationRecord
  belongs_to :user
  has_one_attached :audio

  validates :title, :artist, :audio, presence: true
end
