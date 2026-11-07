class Balloon < ApplicationRecord
  # 風データを取る範囲（日本周辺）。この外から飛ばすと、風がなくて動かない
  LATITUDES = 20..50
  LONGITUDES = 122..148

  belongs_to :user
  belongs_to :track

  validates :origin_label, presence: true
  validates :origin_lat, numericality: { in: LATITUDES }
  validates :origin_lng, numericality: { in: LONGITUDES }

  before_validation on: :create do
    self.lat = origin_lat
    self.lng = origin_lng
    self.launched_at = self.moved_at = Time.current
  end
end
