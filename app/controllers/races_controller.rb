class RacesController < ApplicationController
  def index
    @races = Race.includes(:circuit).order(season: :desc, round: :asc)
  end

  def show
    @race = Race.includes(:circuit, race_entries: { driver: :constructor }).find(params[:id])
    @entries = @race.race_entries.by_grid
    @predictions = @race.predictions.of_type("race_winner").includes(driver: :constructor).ranked
  end
end
