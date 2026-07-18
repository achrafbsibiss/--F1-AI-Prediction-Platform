class Constructor < ApplicationRecord
  has_many :drivers, dependent: :restrict_with_error
  has_many :race_entries, dependent: :restrict_with_error

  validates :name, presence: true

  def team_color
    color.presence || "#64748b"
  end
end
