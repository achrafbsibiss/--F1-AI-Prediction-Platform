class AddImageCreditToDrivers < ActiveRecord::Migration[7.2]
  def change
    # Portraits come from Wikimedia Commons under CC licenses that require
    # attribution. Storing the credit alongside the URL is what makes the image
    # legal to display, so these travel together or not at all.
    add_column :drivers, :image_attribution, :string
    add_column :drivers, :image_license, :string
    add_column :drivers, :image_source_url, :string
  end
end
