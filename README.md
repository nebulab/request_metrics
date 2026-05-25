# RequestMetrics

Per-request metric tracking and structured log summaries for Rails controllers.

Subclass `RequestMetrics::Base`, declare counters with `metric_accessor`, implement `#log` to record each event, and Rails will append a summary to every `process_action` log line — zero boilerplate.

```
Completed 200 OK in 142ms (Views: 0.5ms | GQL: 87.3ms, 44 cost | Loop API: 31.1ms)
```

## Installation

Add to your Gemfile:

```ruby
gem "request_metrics"
```

No initializer needed. A Railtie installs all registered subclasses into `ActionController::Base` automatically.

## Usage

### 1. Subclass `RequestMetrics::Base`

```ruby
class MyServiceMetrics < RequestMetrics::Base
  metric_accessor :my_service_runtime  # declares counter + thread-safe accessors

  # Called on each tracked event — add to the counter and log the line
  def log(ms:, url:, status:)
    add_my_service_runtime(ms)
    name = color("  MyService (#{ms.round(1)}ms)", YELLOW, bold: true)
    debug "#{name}  #{url} (status: #{status})"
  end

  # Optional — return a string to append to the controller summary log line
  def self.summary_log(payload)
    ms = payload[:my_service_runtime] || 0
    "MyService: #{ms.round(1)}ms" if ms > 0
  end
end
```

### 2. Call `.log` from your HTTP client or wherever the event occurs

```ruby
ms = ActiveSupport::Benchmark.realtime(:float_millisecond) { response = do_request }
MyServiceMetrics.log(ms:, url:, status: response.code)
```

### 3. Filter noise from source location output

`verbose_query_logs` (default `true`) appends a `↳ app/...` caller hint below each log line. Add silencers to suppress framework internals:

```ruby
class MyServiceMetrics < RequestMetrics::Base
  backtrace_cleaner.add_silencer { |line| line.include?("app/clients/") }
  backtrace_cleaner.add_silencer { |line| line.include?("app/models/concerns/") }
  # ...
end
```

---

## Real-world examples

These are the two metrics classes from a Rails + Shopify app.

### Loop API (HTTP client tracking)

Tracks every outbound call to the [Loop Subscriptions](https://loopsubscriptions.com/) API, including cached responses.

```ruby
class LoopControllerMetrics < RequestMetrics::Base
  backtrace_cleaner.add_silencer { |line| line.include?(__FILE__) }
  backtrace_cleaner.add_silencer { |line| line.include?("app/clients/") }
  backtrace_cleaner.add_silencer { |line| line.include?("app/models/concerns/") }
  backtrace_cleaner.add_silencer { |line| line.include?("config/initializers/") }

  metric_accessor :loop_runtime

  def log(method:, url:, ms:, status:, data: nil, cached: false)
    add_loop_runtime(ms)

    http_color =
      case status.to_i
      when 200..299 then GREEN
      when 300..399 then CYAN
      when 400..499 then YELLOW
      when 500..599 then RED
      else               MAGENTA
      end

    name    = color("  #{cached ? "CACHE " : ""}Loop API (#{ms.round(1)}ms)", YELLOW, bold: true)
    request = color("#{method} #{url}", http_color, bold: true)

    debug "#{name}  #{request} #{data&.to_json} (status: #{status})"
  end

  def self.summary_log(payload)
    ms = payload[:loop_runtime] || 0
    "Loop API: #{ms.round(1)}ms" if ms > 0
  end
end
```

Called from the HTTP client:

```ruby
ms = ActiveSupport::Benchmark.realtime(:float_millisecond) { perform.call }
LoopControllerMetrics.log(method: request.method, url: uri.to_s, ms:, status: response.code, data:)
```

Cached hits are logged with zero ms and `CACHE` prefix:

```ruby
LoopControllerMetrics.log(method: method.upcase, url:, ms: 0, status: 200, cached: true)
```

### Shopify GraphQL (API client patching)

Tracks every Shopify Admin API GraphQL call, including query cost. Patches the official `shopify_api` gem's client via `prepend`.

```ruby
class ShopifyGraphqlMetrics < RequestMetrics::Base
  backtrace_cleaner.add_silencer { |line| line.include?(__FILE__) }
  backtrace_cleaner.add_silencer { |line| line.include?("app/models/shop.rb") }
  backtrace_cleaner.add_silencer { |line| line.include?("app/models/concerns/") }
  backtrace_cleaner.add_silencer { |line| line.include?("config/initializers/") }

  metric_accessor :graphql_runtime
  metric_accessor :graphql_cost

  def self.install!
    super
    require "shopify_api/clients/graphql/admin"
    ShopifyAPI::Clients::Graphql::Client.prepend(ShopifyAPIClientLoggingPatch)
  end

  module ShopifyAPIClientLoggingPatch
    def query(query:, variables: nil, headers: nil, tries: 1, response_as_struct: ShopifyAPI::Context.response_as_struct, debug: false)
      response = nil
      ms = ActiveSupport::Benchmark.realtime(:float_millisecond) { response = super }
      cost = response.body.dig("extensions", "cost")
      ShopifyGraphqlMetrics.log(query:, ms:, cost:, variables:)
      response
    end
  end

  def log(query:, ms:, cost:, variables:, cached: false)
    add_graphql_runtime(ms)
    add_graphql_cost(cost.dig("requestedQueryCost")) if cost

    graphql_color =
      case query
      when /\A\s*mutation/i    then GREEN
      when /\A\s*query/i       then BLUE
      when /\A\s*subscription/i then CYAN
      else                          MAGENTA
      end

    name          = color("  #{cached ? "CACHE " : ""}GraphQL (#{ms.round(1)}ms)", YELLOW, bold: true)
    colored_query = color(query.gsub(/\s+/, " ").strip, graphql_color, bold: true)
    binds         = variables.present? ? "  #{variables.inspect}" : ""
    cost_info     = "\n  ↳ cost: #{cost}" if cost

    debug "#{name}  #{colored_query}#{binds}#{cost_info}"
  end

  def self.summary_log(payload)
    runtime = payload[:graphql_runtime]
    cost    = payload[:graphql_cost]

    if runtime && runtime > 0
      cost_info = cost && cost > 0 ? ", #{cost.round} cost" : ""
      "GQL: #{runtime.round(1)}ms#{cost_info}"
    end
  end
end
```

Result in logs:

```
  GraphQL (87.3ms)  query GetSubscription { ... }  { id: "gid://shopify/..." }
  ↳ cost: {"requestedQueryCost"=>44, ...}
  ↳ app/models/concerns/loop/subscription/persistence.rb:23:in `find'

Completed 200 OK in 142ms (Views: 0.5ms | GQL: 87.3ms, 44 cost | Loop API: 31.1ms)
```

---

## API reference

### `metric_accessor(name)`

Declares a per-request counter stored in a thread-local. Generates:

| Method | Description |
|---|---|
| `MyMetrics.my_metric` | Read current value (default: `0`) |
| `MyMetrics.my_metric = n` | Set value |
| `MyMetrics.add_my_metric(delta)` | Increment |
| `MyMetrics.reset_my_metric` | Return current value and reset to `0` |

Thread-local keys are namespaced by subclass name, so two subclasses can both declare `metric_accessor :runtime` without collision.

### `#log(**kwargs)` (instance, delegated to class)

Called per event. Must be implemented by subclasses. Raise `NotImplementedError` if not.

### `.summary_log(payload)` (class)

Called once per request after `process_action`. Return a `String` to append to the log summary, or `nil` to skip. Default implementation returns `nil`.

### `.install!` (class)

Called automatically by the Railtie. Can be overridden to do additional setup (e.g., patching a third-party client) — call `super` to preserve the `ActionController` hook.

### `backtrace_cleaner`

Each subclass gets its own `ActiveSupport::BacktraceCleaner` instance (empty by default). Add silencers to filter which stack frame appears in the `↳` hint.

### `verbose_query_logs`

Boolean (default: `true`). Set to `false` to suppress the `↳ source` hint entirely.

---

## Development

```bash
bin/setup    # install dependencies
rake test    # run tests
bin/console  # interactive prompt
```

## License

MIT.
