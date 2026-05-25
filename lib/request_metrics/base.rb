# frozen_string_literal: true

require "active_support/log_subscriber"
require "active_support/backtrace_cleaner"
require "active_support/core_ext/class/attribute"
require "active_support/concern"

module RequestMetrics
  class Base < ActiveSupport::LogSubscriber
    class_attribute :backtrace_cleaner, default: ActiveSupport::BacktraceCleaner.new
    class_attribute :verbose_query_logs, default: true
    class_attribute :metrics, default: []

    def self.metric_accessor(name)
      metrics << name

      subclass = self
      key = :"#{subclass.object_id}/#{name}"

      define_singleton_method(name) { Thread.current[key] ||= 0 }
      define_singleton_method("#{name}=") { |value| Thread.current[key] = value }
      define_singleton_method("reset_#{name}") { send(name).tap { send("#{name}=", 0) } }
      define_singleton_method("add_#{name}") { |delta| send("#{name}=", send(name) + delta) }

      define_method(name) { subclass.send(name) }
      define_method("#{name}=") { |v| subclass.send("#{name}=", v) }
      define_method("reset_#{name}") { subclass.send("reset_#{name}") }
      define_method("add_#{name}") { |delta| subclass.send("add_#{name}", delta) }
    end

    def self.inherited(subclass)
      super

      subclass.backtrace_cleaner = ActiveSupport::BacktraceCleaner.new
      subclass.verbose_query_logs = verbose_query_logs
      subclass.metrics = []

      RequestMetrics.register(subclass)

      controller_runtime_module = Module.new { extend ActiveSupport::Concern }

      controller_runtime_module.class_methods do
        define_method :log_process_action do |payload|
          messages = super(payload)
          subclass.summary_log(payload)&.then { messages << it }
          messages
        end
      end

      controller_runtime_module.define_method :append_info_to_payload do |payload|
        super(payload)
        subclass.metrics.each { |metric| payload[metric] = subclass.send("reset_#{metric}") }
      end

      subclass.const_set :ControllerRuntime, controller_runtime_module
    end

    def self.install!
      runtime_module = const_get(:ControllerRuntime)
      ActiveSupport.on_load(:action_controller) { include runtime_module }
    end

    def self.summary_log(payload)
      nil
    end

    def log(**options)
      raise NotImplementedError, "#{self.class} must implement #log"
    end

    singleton_class.delegate :log, to: :new

    def debug(message)
      logger.debug(message)
      log_query_source if verbose_query_logs
    end

    private

    def log_query_source
      source = query_source_location
      logger.debug("  ↳ #{source}") if source
    end

    def query_source_location
      backtrace_cleaner.first_clean_frame
    end
  end
end
