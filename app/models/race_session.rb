class RaceSession < ApplicationRecord
  KINDS = %w[fp1 fp2 fp3 sprint_qualifying sprint qualifying race].freeze

  belongs_to :race
  has_many :laps, dependent: :destroy

  validates :session_kind, inclusion: { in: KINDS }
  validates :session_kind, uniqueness: { scope: :race_id }
end
