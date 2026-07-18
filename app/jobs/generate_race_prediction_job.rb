class GenerateRacePredictionJob < ApplicationJob
  queue_as :predictions

  retry_on PythonAiService::Unavailable, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound

  def perform(race_id)
    race = Race.includes(:circuit).find(race_id)

    predictions = PredictionService.new(race).generate_race_prediction

    Turbo::StreamsChannel.broadcast_replace_to(
      race.prediction_stream,
      target: "race_#{race.id}_prediction_card",
      partial: "predictions/card",
      locals: { race: race, predictions: predictions }
    )
  end
end
