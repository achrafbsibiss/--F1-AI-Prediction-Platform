class CreateRaces < ActiveRecord::Migration[7.2]
  def change
    create_table :races do |t|
      t.integer :season, null: false
      t.integer :round, null: false
      t.string :name, null: false
      t.references :circuit, null: false, foreign_key: true
      t.datetime :starts_at
      t.string :status, null: false, default: "scheduled"

      t.timestamps
    end

    add_index :races, [ :season, :round ], unique: true
  end
end
