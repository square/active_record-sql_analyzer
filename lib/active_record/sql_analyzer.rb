require_relative './sql_analyzer/monkeypatches/query'
require_relative './sql_analyzer/monkeypatches/tagger'
require_relative './sql_analyzer/analyzer'
require_relative './sql_analyzer/logger'
require_relative './sql_analyzer/compact_logger'
require_relative './sql_analyzer/redacted_logger'
require_relative './sql_analyzer/background_processor'
require_relative './sql_analyzer/configuration'
require_relative './sql_analyzer/redactor'
require_relative './sql_analyzer/backtrace_filter'
require_relative './sql_analyzer/version'

module ActiveRecord
  module SqlAnalyzer
    def self.configure
      @config ||= Configuration.new
      yield @config
      @config
    end

    def self.config
      @config
    end

    def self.background_processor
      @background_processor ||= BackgroundProcessor.new
    end

    def self.install!
      return if @installed
      @installed = true

      # Install our patch that logs SQL queries
      ActiveRecord::ConnectionAdapters::Mysql2Adapter.prepend(Monkeypatches::Query)

      # Install our patch that enables a `with_tag` method on AR calls
      ActiveRecord::Relation.prepend(Monkeypatches::Tagger)
    end
  end
end
