module ActiveRecord
  module SqlAnalyzer
    class RedactedLogger < CompactLogger
      def filter_event(event)
        # Determine if we're doing extended tracing or only the first
        if config[:ambiguous_tracers].any? { |regex| event[:caller].first =~ regex }
          event[:caller] = event[:caller][0, config[:ambiguous_backtrace_lines]].join(", ")
        else
          event[:caller] = event[:caller].first
        end

        config[:backtrace_redactors].each do |redactor|
          event[:caller].gsub!(redactor.search, redactor.replace)
        end

        config[:sql_redactors].each do |redactor|
          event[:sql].gsub!(redactor.search, redactor.replace)
        end
      end
    end
  end
end
