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
        sha = Digest::MD5.hexdigest(event.to_s)
        unless logged_shas.include?(sha)
          definition_log_file.puts("#{sha}|#{event.to_json}")
          logged_shas << sha
        end

        log_file.puts("#{Time.now.to_i}|#{sha}")
      end

      def close
        @definition_log_file.close rescue nil
        super
      end
    end
  end
end
