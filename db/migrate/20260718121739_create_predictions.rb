class CreatePredictions < ActiveRecord::Migration[7.2]
  def change
    create_table :predictions do |t|
      t.references :race, null: false, foreign_key: true
      t.references :driver, null: false, foreign_key: true
      t.string :prediction_type, null: false
      t.decimal :probability, precision: 6, scale: 5, null: false, default: 0
      t.integer :position
      t.string :model_version

      t.timestamps
    end

    # One live prediction row per driver per prediction type, refreshed in place.
    add_index :predictions, [ :race_id, :prediction_type, :driver_id ], unique: true,
              name: "index_predictions_on_race_type_driver"
  end
end
