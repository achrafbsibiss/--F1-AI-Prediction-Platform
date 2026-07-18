class Circuit < ApplicationRecord
  has_many :races, dependent: :destroy

  validates :name, presence: true, uniqueness: true

  def outline?
    outline_points.present?
  end

  # The stored points as an SVG polyline "x,y x,y …" string.
  def outline_path
    return nil unless outline?

    outline_points.map { |x, y| "#{x},#{y}" }.join(" ")
  end

  # Points are normalised into a 0-100 box on the longer axis, so the viewBox
  # has to match the shape's own extent or the track renders stretched.
  def outline_viewbox
    return nil unless outline?

    xs = outline_points.map(&:first)
    ys = outline_points.map(&:last)
    "-4 -4 #{(xs.max + 8).round(2)} #{(ys.max + 8).round(2)}"
  end
end
