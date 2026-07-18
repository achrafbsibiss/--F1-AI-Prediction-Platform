class AddImageUrlToDrivers < ActiveRecord::Migration[7.2]
  def change
    # Optional portrait. Left null by the importer: F1 press photos are
    # copyrighted and are not ours to fetch, so the UI falls back to a
    # generated initials avatar unless a licensed URL is supplied.
    add_column :drivers, :image_url, :string
  end
end
