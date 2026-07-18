# Demo fixtures for local development: a full grid and one race weekend.
#
# The driver/team lineup below is the 2025 season and the starting grid is
# invented, NOT a real qualifying result. Real entries and grids are meant to
# arrive through FetchF1DataJob (FastF1/OpenF1); this file only exists so the
# app has something to render before that pipeline is wired.

TEAMS = {
  "McLaren"      => { country: "United Kingdom", color: "#ff8000" },
  "Ferrari"      => { country: "Italy",          color: "#e8002d" },
  "Red Bull"     => { country: "Austria",        color: "#3671c6" },
  "Mercedes"     => { country: "Germany",        color: "#27f4d2" },
  "Aston Martin" => { country: "United Kingdom", color: "#229971" },
  "Alpine"       => { country: "France",         color: "#00a1e8" },
  "Williams"     => { country: "United Kingdom", color: "#1868db" },
  "Racing Bulls" => { country: "Italy",          color: "#6692ff" },
  "Haas"         => { country: "United States",  color: "#b6babd" },
  "Kick Sauber"  => { country: "Switzerland",    color: "#01c00e" }
}.freeze

DRIVERS = [
  # code, full name, number, country, team
  [ "NOR", "Lando Norris",           4, "United Kingdom", "McLaren" ],
  [ "PIA", "Oscar Piastri",         81, "Australia",      "McLaren" ],
  [ "LEC", "Charles Leclerc",       16, "Monaco",         "Ferrari" ],
  [ "HAM", "Lewis Hamilton",        44, "United Kingdom", "Ferrari" ],
  [ "VER", "Max Verstappen",         1, "Netherlands",    "Red Bull" ],
  [ "TSU", "Yuki Tsunoda",          22, "Japan",          "Red Bull" ],
  [ "RUS", "George Russell",        63, "United Kingdom", "Mercedes" ],
  [ "ANT", "Kimi Antonelli",        12, "Italy",          "Mercedes" ],
  [ "ALO", "Fernando Alonso",       14, "Spain",          "Aston Martin" ],
  [ "STR", "Lance Stroll",          18, "Canada",         "Aston Martin" ],
  [ "GAS", "Pierre Gasly",          10, "France",         "Alpine" ],
  [ "COL", "Franco Colapinto",      43, "Argentina",      "Alpine" ],
  [ "ALB", "Alexander Albon",       23, "Thailand",       "Williams" ],
  [ "SAI", "Carlos Sainz",          55, "Spain",          "Williams" ],
  [ "HAD", "Isack Hadjar",           6, "France",         "Racing Bulls" ],
  [ "LAW", "Liam Lawson",           30, "New Zealand",    "Racing Bulls" ],
  [ "OCO", "Esteban Ocon",          31, "France",         "Haas" ],
  [ "BEA", "Oliver Bearman",        87, "United Kingdom", "Haas" ],
  [ "HUL", "Nico Hulkenberg",       27, "Germany",        "Kick Sauber" ],
  [ "BOR", "Gabriel Bortoleto",      5, "Brazil",         "Kick Sauber" ]
].freeze

# Invented starting grid for the demo race, with a 0-100 form rating used as a
# model feature. Replace with real qualifying results before reading anything
# into the predictions.
GRID = [
  [ "NOR", 1,  96.0 ], [ "PIA", 2,  94.5 ], [ "LEC", 3,  90.0 ], [ "VER", 4,  92.0 ],
  [ "RUS", 5,  88.0 ], [ "HAM", 6,  87.5 ], [ "ALO", 7,  82.0 ], [ "ALB", 8,  80.5 ],
  [ "SAI", 9,  80.0 ], [ "GAS", 10, 78.5 ], [ "HAD", 11, 78.0 ], [ "ANT", 12, 84.0 ],
  [ "TSU", 13, 77.0 ], [ "LAW", 14, 75.5 ], [ "OCO", 15, 74.0 ], [ "BEA", 16, 74.5 ],
  [ "HUL", 17, 73.0 ], [ "STR", 18, 72.0 ], [ "COL", 19, 70.5 ], [ "BOR", 20, 70.0 ]
].freeze

ActiveRecord::Base.transaction do
  constructors = TEAMS.to_h do |name, attrs|
    [ name, Constructor.find_or_create_by!(name: name) { |c| c.assign_attributes(attrs) } ]
  end

  drivers = DRIVERS.to_h do |code, full_name, number, country, team|
    driver = Driver.find_or_initialize_by(code: code)
    driver.update!(
      full_name: full_name,
      number: number,
      country: country,
      constructor: constructors.fetch(team)
    )
    [ code, driver ]
  end

  circuit = Circuit.find_or_initialize_by(name: "Circuit de Spa-Francorchamps")
  circuit.update!(
    country: "Belgium",
    latitude: 50.437222,
    longitude: 5.971389,
    length_km: 7.004,
    corners: 19,
    laps: 44
  )

  # Dated today so the demo always has a race to predict.
  race = Race.find_or_initialize_by(season: Date.current.year, round: 13)
  race.update!(
    name: "Belgian Grand Prix",
    circuit: circuit,
    starts_at: Time.zone.now.change(hour: 15, min: 0),
    status: "scheduled"
  )

  RaceSession::KINDS.each_with_index do |kind, i|
    next if kind.start_with?("sprint")

    session = RaceSession.find_or_initialize_by(race: race, session_kind: kind)
    session.update!(started_at: race.starts_at - (4 - i).days)
  end

  GRID.each do |code, grid_position, pace_rating|
    driver = drivers.fetch(code)
    entry = RaceEntry.find_or_initialize_by(race: race, driver: driver)
    entry.update!(
      constructor: driver.constructor,
      grid_position: grid_position,
      pace_rating: pace_rating,
      status: "entered"
    )
  end

  # Demo logins. Development/test only — the password is public in this repo.
  raise "refusing to seed demo users in production" if Rails.env.production?

  {
    "admin@f1.local" => "admin",
    "premium@f1.local" => "premium_user",
    "user@f1.local" => "user"
  }.each do |email, role|
    User.find_or_initialize_by(email: email).tap do |user|
      user.password = "password123"
      user.role = role
      user.save!
    end
  end
end

puts "Seeded #{Constructor.count} teams, #{Driver.count} drivers, #{Race.count} race(s), #{User.count} users."
puts "Login: admin@f1.local / premium@f1.local / user@f1.local — password123"
