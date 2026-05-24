class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product

  before_validation :copy_unit_price_from_product, on: :create

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :unit_price, presence: true, numericality: { greater_than_or_equal_to: 0 }

  def subtotal
    (unit_price || product&.price || 0) * (quantity || 0)
  end

  private

  def copy_unit_price_from_product
    self.unit_price ||= product&.price
  end
end
