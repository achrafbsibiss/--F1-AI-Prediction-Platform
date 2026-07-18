# Thin HTTP client for the Python FastAPI prediction service.
class PythonAiService
  class Error < StandardError; end
  class Unavailable < Error; end

  TIMEOUT = 15

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

  private

  attr_reader :base_url

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
