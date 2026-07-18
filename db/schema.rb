# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_07_18_125126) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "circuits", force: :cascade do |t|
    t.string "name", null: false
    t.string "country"
    t.decimal "latitude", precision: 9, scale: 6
    t.decimal "longitude", precision: 9, scale: 6
    t.decimal "length_km", precision: 5, scale: 3
    t.integer "corners"
    t.integer "laps"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_circuits_on_name", unique: true
  end

  create_table "constructors", force: :cascade do |t|
    t.string "name"
    t.string "country"
    t.string "color"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "drivers", force: :cascade do |t|
    t.string "full_name", null: false
    t.string "code", null: false
    t.integer "number"
    t.string "country"
    t.bigint "constructor_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_drivers_on_code", unique: true
    t.index ["constructor_id"], name: "index_drivers_on_constructor_id"
  end

  create_table "laps", force: :cascade do |t|
    t.bigint "race_session_id", null: false
    t.bigint "driver_id", null: false
    t.integer "lap_number", null: false
    t.integer "lap_time_ms"
    t.integer "sector_1_ms"
    t.integer "sector_2_ms"
    t.integer "sector_3_ms"
    t.string "compound"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["driver_id"], name: "index_laps_on_driver_id"
    t.index ["race_session_id", "driver_id", "lap_number"], name: "index_laps_on_session_driver_lap", unique: true
    t.index ["race_session_id"], name: "index_laps_on_race_session_id"
  end

  create_table "predictions", force: :cascade do |t|
    t.bigint "race_id", null: false
    t.bigint "driver_id", null: false
    t.string "prediction_type", null: false
    t.decimal "probability", precision: 6, scale: 5, default: "0.0", null: false
    t.integer "position"
    t.string "model_version"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["driver_id"], name: "index_predictions_on_driver_id"
    t.index ["race_id", "prediction_type", "driver_id"], name: "index_predictions_on_race_type_driver", unique: true
    t.index ["race_id"], name: "index_predictions_on_race_id"
  end

  create_table "race_entries", force: :cascade do |t|
    t.bigint "race_id", null: false
    t.bigint "driver_id", null: false
    t.bigint "constructor_id", null: false
    t.integer "grid_position"
    t.integer "finish_position"
    t.string "status", default: "entered", null: false
    t.decimal "pace_rating", precision: 5, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["constructor_id"], name: "index_race_entries_on_constructor_id"
    t.index ["driver_id"], name: "index_race_entries_on_driver_id"
    t.index ["race_id", "driver_id"], name: "index_race_entries_on_race_id_and_driver_id", unique: true
    t.index ["race_id"], name: "index_race_entries_on_race_id"
  end

  create_table "race_sessions", force: :cascade do |t|
    t.bigint "race_id", null: false
    t.string "session_kind", null: false
    t.datetime "started_at"
    t.datetime "ended_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["race_id", "session_kind"], name: "index_race_sessions_on_race_id_and_session_kind", unique: true
    t.index ["race_id"], name: "index_race_sessions_on_race_id"
  end

  create_table "races", force: :cascade do |t|
    t.integer "season", null: false
    t.integer "round", null: false
    t.string "name", null: false
    t.bigint "circuit_id", null: false
    t.datetime "starts_at"
    t.string "status", default: "scheduled", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "demo_data", default: false, null: false
    t.index ["circuit_id"], name: "index_races_on_circuit_id"
    t.index ["season", "round"], name: "index_races_on_season_and_round", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "role", default: "user", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "drivers", "constructors"
  add_foreign_key "laps", "drivers"
  add_foreign_key "laps", "race_sessions"
  add_foreign_key "predictions", "drivers"
  add_foreign_key "predictions", "races"
  add_foreign_key "race_entries", "constructors"
  add_foreign_key "race_entries", "drivers"
  add_foreign_key "race_entries", "races"
  add_foreign_key "race_sessions", "races"
  add_foreign_key "races", "circuits"
end
