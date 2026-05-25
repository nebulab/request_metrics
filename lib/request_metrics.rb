# frozen_string_literal: true

require_relative "request_metrics/version"
require_relative "request_metrics/base"
require_relative "request_metrics/railtie" if defined?(Rails::Railtie)

module RequestMetrics
  class << self
    def registry
      @registry ||= []
    end

    def register(subclass)
      registry << subclass
    end
  end
end
