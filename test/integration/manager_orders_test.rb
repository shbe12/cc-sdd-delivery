require "test_helper"

class ManagerOrdersTest < ActionDispatch::IntegrationTest
  setup do
    OrderItem.delete_all
    Order.delete_all
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

  test "new renders the order form" do
    get new_manager_order_path
    assert_response :success
    assert_select "form"
    assert_select "input[name='order[recipient_name]']"
  end

  test "create persists an order with items and redirects to it" do
    assert_difference [ "Order.count", "OrderItem.count" ], 1 do
      post manager_orders_path, params: {
        order: {
          recipient_name: "Ana", recipient_phone: "55", address: "Colima 143, CDMX",
          order_items_attributes: { "0" => { product_id: @product.id, quantity: "2" } }
        }
      }
    end
    order = Order.last
    assert_redirected_to manager_order_path(order)
    assert_equal 300, order.total            # 150 * 2 snapshot
    assert_equal 150, order.order_items.first.unit_price
  end

  test "create re-renders with errors when invalid" do
    assert_no_difference "Order.count" do
      post manager_orders_path, params: {
        order: { recipient_name: "", recipient_phone: "", address: "" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "show displays the order and an assign-rider form when pending" do
    order = create_order(status: :pending)
    get manager_order_path(order)
    assert_response :success
    assert_select "select[name='order[rider_id]']"
  end

  test "update assigns a rider and moves the order to assigned" do
    order = create_order(status: :pending)
    patch manager_order_path(order), params: { order: { rider_id: @rider.id } }
    assert_redirected_to manager_order_path(order)
    assert order.reload.assigned?
    assert_equal @rider, order.rider
  end

  test "update with a blank rider does not assign and keeps the order pending" do
    order = create_order(status: :pending)
    patch manager_order_path(order), params: { order: { rider_id: "" } }
    assert_redirected_to manager_order_path(order)
    assert order.reload.pending?
  end

  test "show wires the order map element with destination coordinates" do
    order = create_order(status: :assigned, rider: @rider)
    get manager_order_path(order)
    assert_response :success
    assert_select ".order-map[data-controller='map']"
    assert_select ".order-map[data-map-lat-value]"
    assert_select ".order-map[data-map-lng-value]"
  end

  test "manager keeps the shared sidebar layout and gets no rider chrome" do
    get manager_orders_path
    assert_response :success
    assert_select ".sidebar"
    assert_select ".rider-topbar", false
  end
end
