# Thin HTTP client for the Python FastAPI prediction service.
class PythonAiService
  class Error < StandardError; end
  class Unavailable < Error; end

  TIMEOUT = 15
  # FastF1 downloads and caches a whole season on a cold call, which is far
  # slower than inference against an already-loaded model.
  DATA_TIMEOUT = 300

  def initialize(base_url: Rails.configuration.ai_service_url)
    @base_url = base_url
  end

  def healthy?
    connection.get("/health").success?
  rescue Faraday::Error
    false
  end

  # payload: { race:, season:, laps:, drivers: [{ code:, name:, grid:, pace:, team: }] }
  def predict_race(payload)
    post("/predict/race", payload)
  end

  # The service also fronts FastF1 — it is the only process that reads F1 data.
  def season_calendar(season)
    get("/data/season/#{season}")
  end

  def race_entries(season, round)
    get("/data/race/#{season}/#{round}")
  end

  # Slow: generating an outline downloads a session's position telemetry.
  def circuit_outline(season, round)
    get("/data/circuit/#{season}/#{round}/outline", timeout: 600)
  end

  private

  attr_reader :base_url

  def get(path, timeout: DATA_TIMEOUT)
    response = connection.get(path) { |request| request.options.timeout = timeout }

    unless response.success?
      raise Error, "AI service #{path} returned #{response.status}: #{response.body}"
    end

    response.body
  rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
    raise Unavailable, "AI service unreachable at #{base_url}: #{e.message}"
  end

  def post(path, payload)
    response = connection.post(path, payload)

    unless response.success?
      raise Error, "AI service #{path} returned #{response.status}: #{response.body}"
    end

    response.body
  rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
    raise Unavailable, "AI service unreachable at #{base_url}: #{e.message}"
  end

  def connection
    @connection ||= Faraday.new(url: base_url) do |f|
      f.request :json
      f.response :json
      f.request :retry, max: 2, interval: 0.2, backoff_factor: 2
      f.options.timeout = TIMEOUT
      f.options.open_timeout = 5
    end
  end
end
