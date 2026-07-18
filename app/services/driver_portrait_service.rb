# Fetches driver portraits from Wikimedia Commons.
#
# Official F1 press photos are copyrighted and can't be reused, so this pulls
# the portrait off each driver's Wikipedia page instead — but only when the
# license actually permits reuse, and only while recording the attribution the
# license demands. An image whose license can't be confirmed is skipped rather
# than displayed.
class DriverPortraitService
  API = "https://en.wikipedia.org/w/api.php".freeze

  # Licenses that allow reuse with attribution. Anything else (notably the
  # "fair use" logos and press shots Wikipedia hosts non-freely) is rejected.
  ALLOWED_LICENSES = /\A(cc-by|cc-zero|cc-sa|pd|public domain)/i
  # extmetadata sometimes leaves License blank and names the terms only in
  # LicenseShortName, e.g. the UK Open Government Licence.
  ALLOWED_LICENSE_NAMES = /\A(cc |ogl|public domain|cc0)/i

  MAX_WIDTH = 400

  # Wikipedia rate-limits bursts; anything faster than this starts failing.
  REQUEST_DELAY = 0.5

  def initialize(user_agent: "F1PredictionsDemo/1.0 (local development)")
    @user_agent = user_agent
  end

  def import_all(drivers = Driver.all)
    drivers.filter_map do |driver|
      result = import(driver)
      sleep REQUEST_DELAY
      result
    end
  end

  # Returns the driver on success, nil when no usable image was found.
  def import(driver)
    file = candidate_titles(driver).lazy.filter_map { |title| page_image_file(title) }.first
    # Wikipedia's title may not be the name FastF1 reports ("Nico Hulkenberg"
    # vs "Nico Hülkenberg", "Carlos Sainz" vs "Carlos Sainz Jr."), so fall back
    # to searching rather than giving up on an exact match.
    file ||= page_image_file(search_title(driver))
    return nil if file.blank?

    info = image_info(file)
    return nil if info.blank?

    unless reusable_license?(info)
      Rails.logger.info(
        "Skipping #{driver.code} portrait: license #{info[:license_name].presence || "unknown"}"
      )
      return nil
    end

    driver.update!(
      image_url: info[:url],
      image_attribution: info[:artist],
      image_license: info[:license_name],
      image_source_url: info[:descriptionurl]
    )
    driver
  rescue Faraday::Error => e
    Rails.logger.warn("Portrait lookup failed for #{driver.code}: #{e.message}")
    nil
  end

  private

  attr_reader :user_agent

  # Several drivers share a name with someone more famous, so the plain name
  # can land on a disambiguation page that has no portrait.
  def candidate_titles(driver)
    [ driver.full_name, "#{driver.full_name} (racing driver)", "#{driver.full_name} (driver)" ]
  end

  # Best-matching article title for a driver, via Wikipedia search.
  def search_title(driver)
    body = get(
      action: "query",
      list: "search",
      srsearch: "#{driver.full_name} Formula One driver",
      srlimit: 1,
      format: "json"
    )

    body.dig("query", "search", 0, "title")
  end

  def reusable_license?(info)
    info[:license].to_s.match?(ALLOWED_LICENSES) ||
      info[:license_name].to_s.match?(ALLOWED_LICENSE_NAMES)
  end

  def page_image_file(title)
    body = get(
      action: "query",
      titles: title,
      prop: "pageimages",
      piprop: "name",
      redirects: 1,
      format: "json"
    )

    page = body.dig("query", "pages")&.values&.first
    page&.dig("pageimage")
  end

  def image_info(file_name)
    body = get(
      action: "query",
      titles: "File:#{file_name}",
      prop: "imageinfo",
      iiprop: "extmetadata|url",
      iiurlwidth: MAX_WIDTH,
      format: "json"
    )

    info = body.dig("query", "pages")&.values&.first&.dig("imageinfo", 0)
    return nil if info.blank?

    meta = info["extmetadata"] || {}

    {
      # thumburl is the resized copy; full-size portraits are multi-megabyte.
      url: info["thumburl"].presence || info["url"],
      descriptionurl: info["descriptionurl"],
      license: meta.dig("License", "value"),
      license_name: meta.dig("LicenseShortName", "value"),
      artist: strip_markup(meta.dig("Artist", "value"))
    }
  end

  def strip_markup(value)
    return nil if value.blank?

    ActionView::Base.full_sanitizer.sanitize(value.to_s).squish.presence
  end

  def get(params)
    response = connection.get("", params)

    unless response.success?
      # Silently returning {} here made a throttled run look like "no image
      # exists" for every driver, which is a much more misleading failure.
      Rails.logger.warn("Wikipedia API #{response.status} for #{params[:titles]}")
      return {}
    end

    response.body
  end

  def connection
    @connection ||= Faraday.new(url: API, headers: { "User-Agent" => user_agent }) do |f|
      f.response :json
      f.request :retry,
                max: 3,
                interval: 1.0,
                backoff_factor: 2,
                retry_statuses: [ 429, 503 ],
                exceptions: [ Faraday::TimeoutError, Faraday::ConnectionFailed ]
      f.options.timeout = 20
    end
  end
end
