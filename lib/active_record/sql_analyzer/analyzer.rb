module ActiveRecord
  module SqlAnalyzer
    class Analyzer
      attr_reader :options

      def initialize
        @options = {}
      end

      def [](key)
        @options[key]
      end

      # Tables to watch for this analyzer
      def tables(names)
        unless names.is_a?(Array)
          raise ArgumentError, "Names of tables must be an array"
        end

        @options[:table_regex] = /\A\s*((SELECT|DELETE).*(FROM|JOIN)|(INSERT\s+INTO|UPDATE))\s+`?(#{names.join('|')})`?/i
      end

      # Logger class to use for recording data
      def logger(klass)
        @options[:logger] = klass
      end

      # How to tag the data
      def name(name)
        if !name.is_a?(String) && name !~ /\A([a-z0-9A-Z_]+)\z/
          raise ArgumentError, "Name for this analyzer can only contain [a-z0-9A-Z_] characters"
        end

        @options[:name] = name
      end

      def setup
        @options[:logger_instance] ||= (@options[:logger] || RedactedLogger).new(
          SqlAnalyzer.config[:logger_root_path],
          @options[:name]
        )
      end
    end
  end
end
