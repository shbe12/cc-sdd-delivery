class Order < ApplicationRecord
  enum :status, { pending: 0, assigned: 1, en_route: 2, delivered: 3 }, default: :pending

  belongs_to :rider, class_name: "User", optional: true

  validates :recipient_name, :recipient_phone, :address, presence: true
end
