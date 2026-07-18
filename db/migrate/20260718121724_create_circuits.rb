class CreateCircuits < ActiveRecord::Migration[7.2]
  def change
    create_table :circuits do |t|
      t.string :name, null: false
      t.string :country
      t.decimal :latitude, precision: 9, scale: 6
      t.decimal :longitude, precision: 9, scale: 6
      t.decimal :length_km, precision: 5, scale: 3
      t.integer :corners
      t.integer :laps

      t.timestamps
    end

    add_index :circuits, :name, unique: true
  end
end
