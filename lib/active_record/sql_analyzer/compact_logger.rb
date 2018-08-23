require "digest"

module ActiveRecord
  module SqlAnalyzer
    class CompactLogger < Logger
      attr_reader :logged_shas, :definition_log_file

      def initialize(*)
        super

        @logged_shas = Set.new
        @definition_log_file = File.open("#{log_root}/#{log_prefix}_definitions.log", "a+")
      end

      def log(event)
        json = event.to_json
        sha = json.hash
        unless logged_shas.include?(sha)
          definition_log_file.print("#{sha}|#{json}\n")
          logged_shas << sha
        end

        log_file.print("#{Time.now.to_i}|#{sha}\n")
      end

      def close
        @definition_log_file.close rescue nil
        super
      end
    end
  end
end
