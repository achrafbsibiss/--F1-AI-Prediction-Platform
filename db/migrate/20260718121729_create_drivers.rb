class CreateDrivers < ActiveRecord::Migration[7.2]
  def change
    create_table :drivers do |t|
      t.string :full_name, null: false
      t.string :code, null: false
      t.integer :number
      t.string :country
      t.references :constructor, null: false, foreign_key: true

      t.timestamps
    end

    add_index :drivers, :code, unique: true
  end
end
