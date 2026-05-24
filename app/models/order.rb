class Order < ApplicationRecord
  enum :status, { pending: 0, assigned: 1, en_route: 2, delivered: 3 }, default: :pending

  belongs_to :rider, class_name: "User", optional: true
  has_many :order_items, dependent: :destroy
  accepts_nested_attributes_for :order_items, allow_destroy: true, reject_if: :all_blank

  validates :recipient_name, :recipient_phone, :address, presence: true
  validate :must_have_at_least_one_item

  def total
    order_items.reject(&:marked_for_destruction?).sum(&:subtotal)
  end

  def assign_to!(rider)
    return false unless pending?

    update(rider: rider, status: :assigned)
  end

  def mark_en_route!
    return false unless assigned?

    update(status: :en_route)
  end

  def mark_delivered!
    return false unless en_route?

    update(status: :delivered)
  end

  private

  def must_have_at_least_one_item
    return if order_items.reject(&:marked_for_destruction?).any?

    errors.add(:base, "must have at least one item")
  end
end
