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

    def new
      @order = Order.new
      @order.order_items.build
      @products = Product.order(:name)
    end

    def create
      @order = Order.new(order_params)
      if @order.save
        redirect_to manager_order_path(@order), notice: "Orden creada."
      else
        @products = Product.order(:name)
        render :new, status: :unprocessable_entity
      end
    end

    private

    def order_params
      params.require(:order).permit(
        :recipient_name, :recipient_phone, :address,
        order_items_attributes: %i[id product_id quantity _destroy]
      )
    end
  end
end
