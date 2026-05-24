require "test_helper"

class ManagerOrdersTest < ActionDispatch::IntegrationTest
  setup do
    @manager = User.create!(email: "boss@example.com", password: "password123", role: :manager)
    @rider = User.create!(email: "rider@example.com", password: "password123", role: :rider)
    @product = Product.create!(name: "Margarita", price: 150)
    sign_in @manager
  end

  def create_order(status: :pending, rider: nil)
    order = Order.new(recipient_name: "Ana", recipient_phone: "55", address: "CDMX", status: status, rider: rider)
    order.order_items.build(product: @product, quantity: 2)
    order.save!
    order
  end

  test "index shows every order grouped by status" do
    create_order(status: :pending)
    create_order(status: :delivered, rider: @rider)
    get manager_orders_path
    assert_response :success
    assert_select ".kanban-column", 4
    assert_select ".order-card", 2
  end
end
