class User < ApplicationRecord
  ROLES = %w[user premium_user admin].freeze

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  validates :role, inclusion: { in: ROLES }

  def admin?
    role == "admin"
  end

  # Live predictions, AI explanations and the championship simulator are paid features.
  def premium?
    role.in?(%w[premium_user admin])
  end
end
