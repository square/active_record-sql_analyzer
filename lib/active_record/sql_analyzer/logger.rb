module ActiveRecord
  module SqlAnalyzer
    class Logger
      attr_reader :log_file, :log_prefix, :log_root, :config

      def initialize(log_root, log_prefix)
        @log_prefix = log_prefix
        @log_root = log_root
        @config = SqlAnalyzer.config

        @log_file = File.open("#{log_root}/#{log_prefix}.log", "a")
      end

      # Log the raw event data directly to disk
      def log(event)
        log_file.puts(event.to_json)
      end

      # Further redact or remove any other information from an event
      def filter_event(event)
        event
      end

      def close
        @log_file.close rescue nil
      end
    end
  end
end
