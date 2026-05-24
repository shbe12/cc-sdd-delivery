module Manager
  class OrdersController < Manager::BaseController
    STATUS_LABELS = {
      "pending" => "Pendiente",
      "assigned" => "Asignada",
      "en_route" => "En camino",
      "delivered" => "Entregada"
    }.freeze

    def index
      orders = Order.includes(:rider, order_items: :product).order(created_at: :desc)
      @orders_by_status = orders.group_by(&:status)
    end
  end
end
