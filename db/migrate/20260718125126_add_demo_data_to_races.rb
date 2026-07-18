class AddDemoDataToRaces < ActiveRecord::Migration[7.2]
  def change
    # Marks a race whose entries/grid are fixtures rather than fetched results,
    # so the UI can say so instead of presenting invented data as real.
    add_column :races, :demo_data, :boolean, null: false, default: false
  end
end
