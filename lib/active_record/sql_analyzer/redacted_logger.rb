module ActiveRecord
  module SqlAnalyzer
    class RedactedLogger < CompactLogger
      def filter_event(event)
        # Determine if we're doing extended tracing or only the first
        event[:caller] = event[:caller].map do |kaller|
          if config[:ambiguous_tracers].any? { |regex| kaller.first =~ regex }
            kaller[0, config[:ambiguous_backtrace_lines]].join(", ")
          else
            kaller.first
          end
        end.join(';; ')

        config[:backtrace_redactors].each do |redactor|
          event[:caller].gsub!(redactor.search, redactor.replace) if event[:caller]
        end

        config[:sql_redactors].each do |redactor|
          event[:sql].each do |sql|
            sql.gsub!(redactor.search, redactor.replace)
          end
        end

        if event[:sql].size == 1
          event[:sql] = event[:sql].first
        else
          event[:sql] = event[:sql].join('; ') + ';'
        end
      end
    end
  end
end
