class Prediction < ApplicationRecord
  TYPES = %w[race_winner podium top10 fastest_lap dnf pole sprint_winner].freeze

  belongs_to :race
  belongs_to :driver

  validates :prediction_type, inclusion: { in: TYPES }
  validates :probability, numericality: { in: 0..1 }

  scope :of_type, ->(type) { where(prediction_type: type) }
  scope :ranked, -> { order(probability: :desc) }

  def percentage
    (probability * 100).round(1)
  end

  # "0.0%" reads as "impossible" when it really means "rounds to nothing".
  def display_percentage
    percentage.positive? ? "#{percentage}%" : "<0.1%"
  end
end
