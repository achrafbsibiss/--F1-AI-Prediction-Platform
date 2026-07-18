class CreateConstructors < ActiveRecord::Migration[7.2]
  def change
    create_table :constructors do |t|
      t.string :name
      t.string :country
      t.string :color

      t.timestamps
    end
  end
end
