# Imports real F1 data (calendar, entry lists, grids) into Postgres.
#
# All F1 data access lives in the Python service, which fronts FastF1; this
# class only maps that JSON onto our tables. Everything is upserted by natural
# key so an import can be re-run after qualifying without duplicating anything.
class F1DataService
  # FastF1 team names don't always match a display name we want to keep.
  TEAM_COLORS = {
    "McLaren" => "#ff8000",
    "Ferrari" => "#e8002d",
    "Red Bull Racing" => "#3671c6",
    "Mercedes" => "#27f4d2",
    "Aston Martin" => "#229971",
    "Alpine" => "#00a1e8",
    "Williams" => "#1868db",
    "Racing Bulls" => "#6692ff",
    "Haas F1 Team" => "#b6babd",
    "Audi" => "#00e701",
    "Cadillac" => "#c9a227"
  }.freeze

  def initialize(ai_service: PythonAiService.new)
    @ai_service = ai_service
  end

  def healthy_backend?
    ai_service.healthy?
  end

  # Creates/updates every race on the calendar. Entry lists are not fetched
  # here — that is one FastF1 session load per race, so it is done per race.
  def import_season(season)
    payload = ai_service.season_calendar(season)

    payload.fetch("races").map do |race_data|
      circuit = upsert_circuit(race_data)
      upsert_race(season, race_data, circuit)
    end
  end

  # Fetches the entry list for one race: drivers, teams, grid slots, form.
  # Returns the race, or nil when the entry list isn't published yet.
  def import_race_entries(season, round)
    payload = ai_service.race_entries(season, round)

    circuit = upsert_circuit(payload)
    race = upsert_race(season, payload, circuit)

    entries = payload.fetch("entries")
    entries.each { |entry_data| upsert_entry(race, entry_data) }

    # Drop anyone no longer on the entry list (driver swaps mid-season).
    race.race_entries.where.not(driver_id: driver_ids_for(entries)).destroy_all

    race.update!(grid_source: payload["grid_source"], demo_data: false)
    race
  rescue PythonAiService::Error => e
    raise unless e.message.include?("404")

    Rails.logger.info("No entry list yet for #{season} round #{round}")
    nil
  end

  # Traces and caches the track shape. Slow (telemetry download), so it is a
  # separate step rather than part of the entry-list import.
  # Returns the circuit, or nil when no telemetry exists for it.
  def import_circuit_outline(season, round)
    race = Race.find_by(season: season, round: round)
    return nil if race.nil?

    payload = ai_service.circuit_outline(season, round)
    race.circuit.update!(
      outline_points: payload.fetch("points"),
      outline_season: payload["season"]
    )
    race.circuit
  rescue PythonAiService::Error => e
    raise unless e.message.include?("404")

    Rails.logger.info("No telemetry for #{season} round #{round}")
    nil
  end

  private

  attr_reader :ai_service

  def upsert_circuit(data)
    name = data["location"].presence || data["name"]

    Circuit.find_or_initialize_by(name: name).tap do |circuit|
      circuit.country = data["country"]
      circuit.save!
    end
  end

  def upsert_race(season, data, circuit)
    Race.find_or_initialize_by(season: season, round: data.fetch("round")).tap do |race|
      race.name = data.fetch("name")
      race.circuit = circuit
      race.starts_at ||= Time.zone.parse("#{data.fetch("date")} 14:00")
      race.status = race.starts_at&.past? ? "finished" : "scheduled"
      race.save!
    end
  end

  def upsert_entry(race, data)
    constructor = upsert_constructor(data.fetch("team"))
    driver = upsert_driver(data, constructor)

    entry = RaceEntry.find_or_initialize_by(race: race, driver: driver)
    entry.update!(
      constructor: constructor,
      grid_position: data["grid"],
      pace_rating: data["pace"],
      finish_position: data["finish"],
      points: data["points"],
      status: data["status"].presence || entry.status
    )
  end

  def upsert_constructor(name)
    Constructor.find_or_initialize_by(name: name).tap do |constructor|
      constructor.color ||= TEAM_COLORS[name]
      constructor.save!
    end
  end

  def upsert_driver(data, constructor)
    Driver.find_or_initialize_by(code: data.fetch("code")).tap do |driver|
      driver.full_name = data.fetch("name")
      driver.number = data["number"]
      driver.country = data["country"] if data["country"].present?
      driver.constructor = constructor # a driver's team can change mid-season
      driver.save!
    end
  end

  def driver_ids_for(entries)
    Driver.where(code: entries.map { |entry| entry["code"] }).pluck(:id)
  end
end
