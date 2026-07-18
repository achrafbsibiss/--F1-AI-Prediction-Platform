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

  desc "Trace circuit maps from telemetry: rake 'f1:maps[2026]' (slow — ~1 min per new circuit)"
  task :maps, [ :season ] => :environment do |_task, args|
    season = (args[:season] || Date.current.year).to_i
    service = F1DataService.new

    races = Race.for_season(season).includes(:circuit)
    todo = races.reject { |race| race.circuit.outline? }

    if todo.empty?
      puts "All #{races.size} circuits already have an outline."
      next
    end

    puts "Tracing #{todo.size} circuits — each downloads a session's telemetry."

    todo.each do |race|
      circuit = service.import_circuit_outline(season, race.round)
      puts "  R#{race.round} #{race.circuit.name}: #{circuit ? "traced (#{circuit.outline_season})" : "no telemetry"}"
    rescue PythonAiService::Error => e
      puts "  R#{race.round} #{race.circuit.name}: failed — #{e.message.truncate(80)}"
    end
  end

  desc "Import results for completed races: rake 'f1:results[2026]'"
  task :results, [ :season ] => :environment do |_task, args|
    season = (args[:season] || Date.current.year).to_i
    service = F1DataService.new

    Race.for_season(season).where(starts_at: ..Time.current).find_each do |race|
      updated = service.import_race_entries(season, race.round)
      next puts "  R#{race.round}: no data" if updated.nil?

      winner = updated.winner
      puts "  R#{race.round} #{updated.name}: #{winner ? "#{winner.driver.full_name} won" : "no classification"}"
    end
  end

  desc "Fetch CC-licensed driver portraits: rake f1:portraits or rake 'f1:portraits[all]'"
  task :portraits, [ :scope ] => :environment do |_task, args|
    # Only the drivers still missing a portrait, so a run throttled by the
    # Wikipedia API can simply be repeated until it converges.
    drivers = args[:scope] == "all" ? Driver.all : Driver.where(image_url: nil)

    if drivers.none?
      puts "All #{Driver.count} drivers already have a portrait."
      next
    end

    imported = DriverPortraitService.new.import_all(drivers)
    puts "Fetched #{imported.size} of #{drivers.size} attempted."

    missing = Driver.where(image_url: nil).pluck(:code)
    if missing.any?
      puts "Still missing: #{missing.join(", ")} — re-run to retry (API throttling)."
    else
      puts "All #{Driver.count} drivers have a portrait."
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
