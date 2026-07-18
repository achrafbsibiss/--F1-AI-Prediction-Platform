class Race < ApplicationRecord
  STATUSES = %w[scheduled live finished].freeze

  belongs_to :circuit

  has_many :race_entries, dependent: :destroy
  has_many :drivers, through: :race_entries
  has_many :race_sessions, dependent: :destroy
  has_many :predictions, dependent: :destroy

  validates :season, :round, :name, presence: true
  validates :round, uniqueness: { scope: :season }
  validates :status, inclusion: { in: STATUSES }

  scope :upcoming, -> { where(status: "scheduled").order(:starts_at) }
  scope :for_season, ->(season) { where(season: season).order(:round) }

  def to_s
    "#{season} #{name}"
  end

  # Turbo Stream channel the prediction card broadcasts on.
  def prediction_stream
    "race_#{id}_predictions"
  end
end
