# Seeds the demo logins, then imports real F1 data.
#
# Nothing here invents drivers, teams or grids: the calendar and entry lists
# come from FastF1 through the Python service, so what you see is the actual
# season. That means the AI service must be running (bin/dev or uvicorn on
# port 8000) when you seed.

# Demo logins. Development/test only — the password is public in this repo.
raise "refusing to seed demo users in production" if Rails.env.production?

{
  "admin@f1.local" => "admin",
  "premium@f1.local" => "premium_user",
  "user@f1.local" => "user"
}.each do |email, role|
  User.find_or_initialize_by(email: email).tap do |user|
    user.password = "password123"
    user.role = role
    user.save!
  end
end

puts "Users: #{User.count} (password123)"

season = Date.current.year
service = F1DataService.new

unless service.healthy_backend?
  puts "AI service unreachable — skipping F1 import. Start it, then run:"
  puts "  rake 'f1:calendar[#{season}]' && rake 'f1:next[#{season}]'"
  return
end

races = service.import_season(season)
puts "Calendar: #{races.size} races imported for #{season}."

# Entry lists are one FastF1 session load each, so only fetch the next race.
upcoming = Race.for_season(season).where(starts_at: Time.current..).first
upcoming ||= Race.for_season(season).last

if upcoming
  race = service.import_race_entries(season, upcoming.round)
  if race
    puts "#{race}: #{race.race_entries.count} entries, grid from #{race.grid_source}."
  else
    puts "#{upcoming}: no entry list published yet."
  end
end
