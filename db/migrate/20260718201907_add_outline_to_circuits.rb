class AddOutlineToCircuits < ActiveRecord::Migration[7.2]
  def change
    # Track shape as [[x, y], ...] in a 0-100 box, traced from position
    # telemetry. Cached because generating it costs a ~50s telemetry download,
    # which is far too slow to do during a request.
    add_column :circuits, :outline_points, :jsonb
    # Which season's telemetry the shape came from — a circuit can be relaid.
    add_column :circuits, :outline_season, :integer
  end
end
