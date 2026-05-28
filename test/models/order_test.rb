require "test_helper"

class OrderTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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

  test "total sums the subtotals of its items" do
    margarita = Product.create!(name: "Margarita", price: 150)
    soda = Product.create!(name: "Coca-Cola", price: 30)
    order = Order.new(valid_attrs)
    order.order_items.build(product: margarita, quantity: 2) # 300
    order.order_items.build(product: soda, quantity: 1)      # 30
    assert_equal 330, order.total
  end

  test "is invalid without at least one item" do
    order = Order.new(valid_attrs)
    assert_not order.valid?
    assert_includes order.errors[:base], "must have at least one item"
  end

  test "is valid with one item" do
    product = Product.create!(name: "Margarita", price: 150)
    order = Order.new(valid_attrs)
    order.order_items.build(product: product, quantity: 1)
    assert order.valid?
  end

  test "geocodes the address on save" do
    order = create_order
    assert_equal 19.4326, order.latitude
    assert_equal(-99.1332, order.longitude)
  end

  test "does not re-geocode when address is unchanged" do
    order = create_order
    order.latitude = 0.0
    order.longitude = 0.0
    order.update!(recipient_name: "Otra persona") # address unchanged
    assert_equal 0.0, order.latitude # geocode callback did not overwrite
  end

  test "assign_to! moves pending -> assigned and sets the rider" do
    rider = User.create!(email: "r@example.com", password: "password123", role: :rider)
    order = create_order
    assert order.assign_to!(rider)
    assert order.reload.assigned?
    assert_equal rider, order.rider
  end

  test "assign_to! is rejected when not pending" do
    rider = User.create!(email: "r2@example.com", password: "password123", role: :rider)
    order = create_order
    order.assign_to!(rider)
    assert_not order.assign_to!(rider) # already assigned
  end

  test "mark_en_route! requires assigned, mark_delivered! requires en_route" do
    rider = User.create!(email: "r3@example.com", password: "password123", role: :rider)
    order = create_order
    assert_not order.mark_en_route!          # still pending
    order.assign_to!(rider)
    assert order.mark_en_route!
    assert order.reload.en_route?
    assert order.mark_delivered!
    assert order.reload.delivered?
  end

  test "mark_en_route! encola un broadcast refresh al canal manager_orders" do
    rider = User.create!(email: "broadcast1@example.com", password: "password123", role: :rider)
    order = create_order
    order.assign_to!(rider)

    assert_enqueued_with(job: Turbo::Streams::BroadcastStreamJob) do
      assert order.mark_en_route!
    end
    assert_equal "manager_orders", enqueued_jobs.last[:args].first
  end

  test "mark_delivered! encola un broadcast refresh al canal manager_orders" do
    rider = User.create!(email: "broadcast2@example.com", password: "password123", role: :rider)
    order = create_order
    order.assign_to!(rider)
    order.mark_en_route!

    assert_enqueued_with(job: Turbo::Streams::BroadcastStreamJob) do
      assert order.mark_delivered!
    end
    assert_equal "manager_orders", enqueued_jobs.last[:args].first
  end

  test "assign_to! no encola broadcast (no es una transición del rider)" do
    rider = User.create!(email: "broadcast3@example.com", password: "password123", role: :rider)
    order = create_order

    assert_no_enqueued_jobs(only: Turbo::Streams::BroadcastStreamJob) do
      assert order.assign_to!(rider)
    end
  end

  test "update sin cambio de status no encola broadcast" do
    order = create_order

    assert_no_enqueued_jobs(only: Turbo::Streams::BroadcastStreamJob) do
      order.update!(recipient_phone: "5599998888")
    end
  end

  private

  def create_order
    product = Product.create!(name: "Margarita", price: 150)
    order = Order.new(valid_attrs)
    order.order_items.build(product: product, quantity: 1)
    order.save!
    order
  end
end
