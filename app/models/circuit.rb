class Circuit < ApplicationRecord
  has_many :races, dependent: :destroy

  validates :name, presence: true, uniqueness: true
end
