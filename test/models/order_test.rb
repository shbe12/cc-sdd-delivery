require "test_helper"

class OrderTest < ActiveSupport::TestCase
  def valid_attrs
    { recipient_name: "Ana Gómez", recipient_phone: "5512345678", address: "Colima 143, CDMX" }
  end

  test "defaults to pending with no rider" do
    order = Order.new(valid_attrs)
    assert order.pending?
    assert_nil order.rider
  end

  test "requires recipient_name, recipient_phone, address" do
    order = Order.new
    assert_not order.valid?
    assert_includes order.errors[:recipient_name], "can't be blank"
    assert_includes order.errors[:recipient_phone], "can't be blank"
    assert_includes order.errors[:address], "can't be blank"
  end

  test "rider is optional" do
    order = Order.new(valid_attrs)
    order.valid?
    assert_empty order.errors[:rider]
  end
end
