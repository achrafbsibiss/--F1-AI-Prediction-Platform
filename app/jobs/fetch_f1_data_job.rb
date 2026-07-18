# Pulls the real entry list and grid for a race.
#
# Run it after qualifying to replace the pre-qualifying form estimate with the
# actual grid, then regenerate the prediction off it.
class FetchF1DataJob < ApplicationJob
  queue_as :default

  retry_on PythonAiService::Unavailable, wait: :polynomially_longer, attempts: 3

  def perform(season, round, predict: false)
    race = F1DataService.new.import_race_entries(season, round)
    return if race.nil?

    GenerateRacePredictionJob.perform_later(race.id) if predict
    race
  end
end
