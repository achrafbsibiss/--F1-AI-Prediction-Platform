class CreateRaceEntries < ActiveRecord::Migration[7.2]
  def change
    create_table :race_entries do |t|
      t.references :race, null: false, foreign_key: true
      t.references :driver, null: false, foreign_key: true
      t.references :constructor, null: false, foreign_key: true
      t.integer :grid_position
      t.integer :finish_position
      t.string :status, null: false, default: "entered"
      # 0-100 form score fed to the model as a feature.
      t.decimal :pace_rating, precision: 5, scale: 2

      t.timestamps
    end

    add_index :race_entries, [ :race_id, :driver_id ], unique: true
  end
end
