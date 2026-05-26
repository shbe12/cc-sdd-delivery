require "test_helper"

class RiderOrdersTest < ActionDispatch::IntegrationTest
  setup do
    OrderItem.delete_all
    Order.delete_all
    @rider = User.create!(email: "rider@example.com", password: "password123", role: :rider)
    @other_rider = User.create!(email: "other@example.com", password: "password123", role: :rider)
    @product = Product.create!(name: "Margarita", price: 150)
    sign_in @rider
  end

  def create_order(rider:, status: :assigned)
    order = Order.new(recipient_name: "Ana", recipient_phone: "55", address: "CDMX", rider: rider, status: status)
    order.order_items.build(product: @product, quantity: 1)
    order.save!
    order
  end

  test "index shows only my active deliveries" do
    create_order(rider: @rider, status: :assigned)
    create_order(rider: @other_rider, status: :assigned)
    get rider_orders_path
    assert_response :success
    # Two assigned orders exist but only the current rider's own one is listed.
    assert_select ".order-card", 1
  end

  test "rider advances assigned -> en_route -> delivered on own order" do
    order = create_order(rider: @rider, status: :assigned)

    patch rider_order_path(order), params: { transition: "en_route" }
    assert order.reload.en_route?

    patch rider_order_path(order), params: { transition: "delivered" }
    assert order.reload.delivered?
    assert_redirected_to rider_orders_path
  end

  test "rider cannot view another rider's order" do
    theirs = create_order(rider: @other_rider, status: :assigned)
    get rider_order_path(theirs)
    assert_response :not_found
  end

  test "rider cannot advance another rider's order" do
    theirs = create_order(rider: @other_rider, status: :assigned)
    patch rider_order_path(theirs), params: { transition: "en_route" }
    assert_response :not_found
    assert theirs.reload.assigned?
  end

  test "rider cannot skip straight to delivered and sees an alert" do
    order = create_order(rider: @rider, status: :assigned)
    patch rider_order_path(order), params: { transition: "delivered" }
    assert_redirected_to rider_orders_path
    assert order.reload.assigned?
  end

  test "show wires the order map element with destination coordinates" do
    order = create_order(rider: @rider, status: :assigned)
    get rider_order_path(order)
    assert_response :success
    assert_select ".order-map[data-controller='map']"
    assert_select ".order-map[data-map-lat-value]"
    assert_select ".order-map[data-map-lng-value]"
  end

  test "show renders order items as a list, not a table" do
    order = create_order(rider: @rider, status: :assigned)
    get rider_order_path(order)
    assert_response :success
    assert_select "ul.rider-items li.rider-items__row"
    assert_select "li.rider-items__row--total", text: /Total/
    assert_select "table.order-items", false
  end

  test "show has no call or navigate action buttons" do
    order = create_order(rider: @rider, status: :assigned)
    get rider_order_path(order)
    assert_response :success
    assert_select "a[href^='tel:']", false
    assert_select "a[href*='google.com/maps']", false
  end

  test "rider pages use the top-bar layout, not the shared sidebar" do
    order = create_order(rider: @rider, status: :assigned)

    get rider_orders_path
    assert_response :success
    assert_select ".rider-topbar"
    assert_select ".sidebar", false

    get rider_order_path(order)
    assert_response :success
    assert_select ".rider-topbar"
    assert_select ".sidebar", false
  end

  test "show renders the primary action button for an active order" do
    order = create_order(rider: @rider, status: :assigned)
    get rider_order_path(order)
    assert_response :success
    assert_select ".rider-detail__actions .rider-detail__cta", text: "Marcar en camino"
  end

  test "show shows a completed state and no action button when delivered" do
    order = create_order(rider: @rider, status: :delivered)
    get rider_order_path(order)
    assert_response :success
    assert_select ".rider-detail__cta", false
    assert_select ".rider-detail__actions .empty-state", text: /Entrega completada/
  end
end
