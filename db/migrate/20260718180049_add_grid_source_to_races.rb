class AddGridSourceToRaces < ActiveRecord::Migration[7.2]
  def change
    # Where the starting grid came from: "qualifying", "race", or
    # "form_estimate" when qualifying hasn't run and the order is a guess.
    # The UI must not present an estimated grid as a result.
    add_column :races, :grid_source, :string
  end
end
