# Turns a Race into an AI request, then persists the returned probabilities.
class PredictionService
  DEFAULT_PACE = 75.0

  def initialize(race, ai_service: PythonAiService.new)
    @race = race
    @ai_service = ai_service
  end

  # Returns the race_winner predictions, ranked.
  def generate_race_prediction
    entries = race.race_entries.includes(:driver).by_grid.to_a
    raise ArgumentError, "#{race} has no entries to predict" if entries.size < 2

    response = ai_service.predict_race(request_payload(entries))
    persist(response, entries)

    race.predictions.of_type("race_winner").includes(driver: :constructor).ranked
  end

  private

  attr_reader :race, :ai_service

  def request_payload(entries)
    {
      race: race.name,
      season: race.season,
      laps: race.circuit.laps,
      drivers: entries.each_with_index.map do |entry, index|
        {
          code: entry.driver.code,
          name: entry.driver.full_name,
          # Entries without a qualifying result line up behind those that have one.
          grid: entry.grid_position || index + 1,
          pace: (entry.pace_rating || DEFAULT_PACE).to_f,
          team: entry.constructor.name
        }
      end
    }
  end

  def persist(response, entries)
    drivers_by_code = entries.index_by { |entry| entry.driver.code }.transform_values(&:driver)
    version = response["model_version"]

    rows = probability_rows(response, drivers_by_code, version)
    return if rows.empty?

    Prediction.upsert_all(
      rows,
      unique_by: :index_predictions_on_race_type_driver,
      update_only: %i[probability position model_version]
    )
  end

  def probability_rows(response, drivers_by_code, version)
    now = Time.current

    {
      "race_winner" => response["win_probabilities"],
      "podium" => response["podium_probabilities"]
    }.flat_map do |type, probabilities|
      ranked = (probabilities || {}).sort_by { |_code, probability| -probability }

      ranked.filter_map.with_index(1) do |(code, probability), position|
        driver = drivers_by_code[code]
        next unless driver

        {
          race_id: race.id,
          driver_id: driver.id,
          prediction_type: type,
          probability: probability,
          position: position,
          model_version: version,
          created_at: now,
          updated_at: now
        }
      end
    end
  end
end
