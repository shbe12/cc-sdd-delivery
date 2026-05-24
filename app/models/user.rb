class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  enum :role, { manager: 0, rider: 1 }, default: :rider

  has_many :assigned_orders, class_name: "Order", foreign_key: :rider_id, dependent: :nullify
end
