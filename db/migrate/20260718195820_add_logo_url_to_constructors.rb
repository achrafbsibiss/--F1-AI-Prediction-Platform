class AddLogoUrlToConstructors < ActiveRecord::Migration[7.2]
  def change
    # Left null deliberately. F1 team logos are registered trademarks and are
    # not published under a reusable license, so nothing populates this
    # automatically — the UI falls back to the team's color bar. Populate it
    # only with assets you are licensed to display.
    add_column :constructors, :logo_url, :string
  end
end
