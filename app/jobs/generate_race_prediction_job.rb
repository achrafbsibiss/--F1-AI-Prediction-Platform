class GenerateRacePredictionJob < ApplicationJob
  queue_as :predictions

  retry_on PythonAiService::Unavailable, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound

  def perform(race_id)
    race = Race.includes(:circuit).find(race_id)

    # Only the races someone has looked at get imported, so a first prediction
    # for any other race arrives with an empty entry list. Fetch it rather than
    # failing — this is the normal path, not an error.
    import_entries(race) if race.race_entries.count < 2

    predictions = PredictionService.new(race).generate_race_prediction
    broadcast(race, predictions: predictions)
  rescue PredictionService::NoEntries
    broadcast(race, error: "No entry list has been published for this race yet.")
  rescue PythonAiService::Error => e
    Rails.logger.error("Prediction failed for race #{race_id}: #{e.message}")
    broadcast(race, error: "The prediction service could not be reached. Try again shortly.")
  end

  private

  def import_entries(race)
    F1DataService.new.import_race_entries(race.season, race.round)
    race.reload
  rescue PythonAiService::Error => e
    # Leave it to the NoEntries path below to report; the import is best-effort.
    Rails.logger.warn("Entry import failed for #{race}: #{e.message}")
  end

  def broadcast(race, predictions: nil, error: nil)
    Turbo::StreamsChannel.broadcast_replace_to(
      race.prediction_stream,
      target: "race_#{race.id}_prediction_card",
      partial: "predictions/card",
      locals: {
        race: race,
        predictions: predictions || race.predictions.of_type("race_winner").ranked,
        error: error
      }
    )
  end
end
