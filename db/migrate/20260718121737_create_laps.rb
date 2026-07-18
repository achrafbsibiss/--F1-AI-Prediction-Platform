class CreateLaps < ActiveRecord::Migration[7.2]
  def change
    create_table :laps do |t|
      t.references :race_session, null: false, foreign_key: true
      t.references :driver, null: false, foreign_key: true
      t.integer :lap_number, null: false
      t.integer :lap_time_ms
      t.integer :sector_1_ms
      t.integer :sector_2_ms
      t.integer :sector_3_ms
      t.string :compound

      t.timestamps
    end

    add_index :laps, [ :race_session_id, :driver_id, :lap_number ], unique: true,
              name: "index_laps_on_session_driver_lap"
  end
end
