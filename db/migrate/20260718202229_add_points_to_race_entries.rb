class AddPointsToRaceEntries < ActiveRecord::Migration[7.2]
  def change
    # Championship points scored. Fractional in a shortened race, so not integer.
    add_column :race_entries, :points, :decimal, precision: 5, scale: 2
  end
end
