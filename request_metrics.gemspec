# frozen_string_literal: true

require_relative "lib/request_metrics/version"

Gem::Specification.new do |spec|
  spec.name = "request_metrics"
  spec.version = RequestMetrics::VERSION
  spec.authors = ["Elia Schito"]
  spec.email = ["elia@schito.me"]

  spec.summary = "Per-request metric tracking and log summaries for Rails controllers"
  spec.description = <<~DESC
    RequestMetrics provides a base class for attaching per-request counters and
    timing metrics to Rails controller log lines. Subclass RequestMetrics::Base,
    declare metrics with metric_accessor, implement #log and .summary_log, and
    the gem wires everything into ActionController via a Railtie automatically.
  DESC
  spec.homepage = "https://github.com/nebulab/request_metrics"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/releases"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", ">= 7.0"
end
