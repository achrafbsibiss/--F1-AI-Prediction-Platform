class Driver < ApplicationRecord
  belongs_to :constructor

  has_many :race_entries, dependent: :destroy
  has_many :races, through: :race_entries
  has_many :laps, dependent: :destroy
  has_many :predictions, dependent: :destroy

  validates :full_name, presence: true
  validates :code, presence: true, uniqueness: true

  def last_name
    full_name.split.last
  end
end
