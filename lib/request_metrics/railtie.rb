# frozen_string_literal: true

require "rails/railtie"

module RequestMetrics
  class Railtie < Rails::Railtie
    initializer "request_metrics.install" do
      ActiveSupport.on_load(:action_controller) do
        RequestMetrics.registry.each(&:install!)
      end
    end
  end
end
