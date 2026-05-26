module Rider
  class BaseController < ApplicationController
    layout "rider"
    before_action :require_rider

    private

    def require_rider
      redirect_to root_path, alert: "No tienes acceso a esa sección." unless current_user.rider?
    end
  end
end
