class Constructor < ApplicationRecord
  has_many :drivers, dependent: :restrict_with_error
  has_many :race_entries, dependent: :restrict_with_error

  validates :name, presence: true

  # FastF1's official entrant names are too long for a list row.
  SHORT_NAMES = {
    "Red Bull Racing" => "Red Bull",
    "Haas F1 Team" => "Haas",
    "Aston Martin" => "Aston Martin"
  }.freeze

  def short_name
    SHORT_NAMES.fetch(name, name)
  end

  def team_color
    color.presence || "#64748b"
  end
end
