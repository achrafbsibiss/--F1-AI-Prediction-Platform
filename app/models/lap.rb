class Lap < ApplicationRecord
  belongs_to :race_session
  belongs_to :driver

  validates :lap_number, presence: true, numericality: { greater_than: 0 }

  scope :timed, -> { where.not(lap_time_ms: nil) }

  def lap_time_seconds
    lap_time_ms && lap_time_ms / 1000.0
  end
end
