# frozen_string_literal: true

require "test_helper"

class TestRequestMetrics < Minitest::Test
  def test_version
    refute_nil RequestMetrics::VERSION
  end
end

class TestRequestMetricsBase < Minitest::Test
  def setup
    # Fresh subclass per test — avoids cross-test pollution via registry/Thread
    @klass = Class.new(RequestMetrics::Base)
    @klass.metric_accessor :call_count
    @klass.metric_accessor :call_runtime
  end

  def teardown
    # Reset thread-locals so tests don't bleed into each other
    @klass.reset_call_count
    @klass.reset_call_runtime
  end

  def test_metric_accessor_starts_at_zero
    assert_equal 0, @klass.call_count
    assert_equal 0, @klass.call_runtime
  end

  def test_add_accumulates
    @klass.add_call_count(1)
    @klass.add_call_count(1)
    assert_equal 2, @klass.call_count
  end

  def test_reset_returns_value_and_clears
    @klass.add_call_count(5)
    returned = @klass.reset_call_count
    assert_equal 5, returned
    assert_equal 0, @klass.call_count
  end

  def test_thread_local_isolation
    other_thread_value = nil

    @klass.add_call_count(42)

    t = Thread.new { other_thread_value = @klass.call_count }
    t.join

    assert_equal 42, @klass.call_count
    assert_equal 0, other_thread_value
  end

  def test_no_key_collision_between_subclasses
    klass_a = Class.new(RequestMetrics::Base)
    klass_b = Class.new(RequestMetrics::Base)
    klass_a.metric_accessor :runtime
    klass_b.metric_accessor :runtime

    klass_a.add_runtime(10)
    klass_b.add_runtime(20)

    assert_equal 10, klass_a.runtime
    assert_equal 20, klass_b.runtime

    klass_a.reset_runtime
    klass_b.reset_runtime
  end

  def test_inherited_sets_up_controller_runtime_module
    assert @klass.const_defined?(:ControllerRuntime)
    mod = @klass.const_get(:ControllerRuntime)
    assert mod.is_a?(Module)
  end

  def test_inherited_gives_each_subclass_own_metrics_list
    klass_a = Class.new(RequestMetrics::Base)
    klass_b = Class.new(RequestMetrics::Base)
    klass_a.metric_accessor :foo
    klass_b.metric_accessor :bar

    assert_includes klass_a.metrics, :foo
    refute_includes klass_a.metrics, :bar
    assert_includes klass_b.metrics, :bar
    refute_includes klass_b.metrics, :foo

    klass_a.reset_foo
    klass_b.reset_bar
  end

  def test_summary_log_returns_nil_by_default
    assert_nil @klass.summary_log({})
  end

  def test_summary_log_can_be_overridden
    @klass.define_singleton_method(:summary_log) { |payload| "custom: #{payload[:x]}" }
    assert_equal "custom: 5", @klass.summary_log({ x: 5 })
  end

  def test_log_raises_not_implemented_error
    instance = @klass.new
    assert_raises(NotImplementedError) { instance.log }
  end

  def test_registers_subclass_in_registry
    klass = Class.new(RequestMetrics::Base)
    assert_includes RequestMetrics.registry, klass
  end

  def test_backtrace_cleaner_is_independent_per_subclass
    klass_a = Class.new(RequestMetrics::Base)
    klass_b = Class.new(RequestMetrics::Base)
    klass_a.backtrace_cleaner.add_silencer { true }

    # klass_b should still have a clean cleaner
    refute_equal klass_a.backtrace_cleaner, klass_b.backtrace_cleaner
  end
end
