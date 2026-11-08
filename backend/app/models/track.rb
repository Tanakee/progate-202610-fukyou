class Track < ApplicationRecord
  belongs_to :user
  has_one_attached :audio
  has_one_attached :thumbnail

  validates :title, :artist, :audio, presence: true
end
