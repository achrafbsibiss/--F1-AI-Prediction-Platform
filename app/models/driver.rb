class Driver < ApplicationRecord
  belongs_to :constructor

  has_many :race_entries, dependent: :destroy
  has_many :races, through: :race_entries
  has_many :laps, dependent: :destroy
  has_many :predictions, dependent: :destroy

  validates :full_name, presence: true
  validates :code, presence: true, uniqueness: true

  def last_name
    full_name.split.last
  end

  # Two-letter monogram for the generated avatar (F1 portraits are licensed
  # media, so nothing is fetched unless image_url is explicitly populated).
  def initials
    parts = full_name.split
    return full_name.first(2).upcase if parts.one?

    "#{parts.first[0]}#{parts.last[0]}".upcase
  end
end
