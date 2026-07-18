module Races
  class PredictionsController < ApplicationController
    before_action :authenticate_user!

    def create
      race = Race.find(params[:race_id])
      GenerateRacePredictionJob.perform_later(race.id)

      redirect_to race_path(race), notice: "Prediction queued — the card updates when the model responds."
    end
  end
end
