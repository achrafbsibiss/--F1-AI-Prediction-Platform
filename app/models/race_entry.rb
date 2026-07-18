class RaceEntry < ApplicationRecord
  belongs_to :race
  belongs_to :driver
  belongs_to :constructor

  validates :driver_id, uniqueness: { scope: :race_id }

  scope :by_grid, -> { order(Arel.sql("grid_position IS NULL, grid_position ASC")) }
end
