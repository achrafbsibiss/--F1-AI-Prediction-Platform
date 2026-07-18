class CreateRaceSessions < ActiveRecord::Migration[7.2]
  def change
    create_table :race_sessions do |t|
      t.references :race, null: false, foreign_key: true
      t.string :session_kind, null: false
      t.datetime :started_at
      t.datetime :ended_at

      t.timestamps
    end

    add_index :race_sessions, [ :race_id, :session_kind ], unique: true
  end
end
