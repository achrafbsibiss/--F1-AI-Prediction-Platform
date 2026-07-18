namespace :f1 do
  desc "Import a season's calendar: rake 'f1:calendar[2026]'"
  task :calendar, [ :season ] => :environment do |_task, args|
    season = (args[:season] || Date.current.year).to_i
    races = F1DataService.new.import_season(season)
    puts "Imported #{races.size} races for #{season}."
  end

  desc "Import one race's entry list and grid: rake 'f1:race[2026,10]'"
  task :race, [ :season, :round ] => :environment do |_task, args|
    season = args.fetch(:season).to_i
    round = args.fetch(:round).to_i

    race = F1DataService.new.import_race_entries(season, round)
    if race
      puts "#{race} — #{race.race_entries.count} entries, grid from #{race.grid_source}."
    else
      puts "No entry list published yet for #{season} round #{round}."
    end
  end

  desc "Import the next upcoming race of a season: rake 'f1:next[2026]'"
  task :next, [ :season ] => :environment do |_task, args|
    season = (args[:season] || Date.current.year).to_i
    service = F1DataService.new

    service.import_season(season) if Race.for_season(season).none?

    race = Race.for_season(season).where(starts_at: Time.current..).first
    abort "No upcoming race found for #{season}." if race.nil?

    service.import_race_entries(season, race.round)
    puts "#{race.reload} — #{race.race_entries.count} entries, grid from #{race.grid_source}."
  end
end
