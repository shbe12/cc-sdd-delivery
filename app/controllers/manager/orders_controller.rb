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

    def show
      @order = Order.includes(order_items: :product).find(params[:id])
      @riders = User.rider.order(:email)
    end

    def update
      @order = Order.find(params[:id])
      rider = User.rider.find(params.dig(:order, :rider_id))
      if @order.assign_to!(rider)
        redirect_to manager_order_path(@order), notice: "Rider asignado."
      else
        redirect_to manager_order_path(@order), alert: "No se pudo asignar el rider."
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
