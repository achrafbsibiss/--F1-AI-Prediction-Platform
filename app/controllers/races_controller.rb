class RacesController < ApplicationController
  def index
    @races = Race.includes(:circuit).order(season: :desc, round: :asc)

    # Winners for the calendar, in one query rather than one per race.
    @winners = RaceEntry.where(race: @races, finish_position: 1)
                        .includes(driver: :constructor)
                        .index_by(&:race_id)
  end

  def show
    @race = Race.includes(:circuit, race_entries: { driver: :constructor }).find(params[:id])
    @entries = @race.race_entries.by_grid
    @predictions = @race.predictions.of_type("race_winner").includes(driver: :constructor).ranked
  end
end
