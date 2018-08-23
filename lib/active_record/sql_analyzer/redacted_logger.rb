module ActiveRecord
  module SqlAnalyzer
    class RedactedLogger < CompactLogger
      def filter_event(event)
        # Determine if we're doing extended tracing or only the first
        calls = event.delete(:calls).map do |call|
          { sql: filter_sql(call[:sql]), caller: filter_caller(call[:caller]) }
        end

        # De-duplicate redacted calls to avoid many transactions with looping "N+1" queries.
        calls.uniq!

        event[:sql] = calls.map { |call| call[:sql] }
        event[:caller] = calls.map { |call| call[:caller] }.join(';; ')

        if event[:sql].size == 1
          event[:sql] = event[:sql].first
        else
          event[:sql] = event[:sql].join('; ') + ';'
        end
      end

      def filter_caller(kaller)
        kaller = if config[:ambiguous_tracers].any? { |regex| kaller.first =~ regex }
                   kaller[0, config[:ambiguous_backtrace_lines]].join(", ")
                 else
                   kaller.first
                 end

        return '' unless kaller

        config[:backtrace_redactors].each do |redactor|
          kaller.gsub!(redactor.search, redactor.replace)
        end

        kaller
      end

      def filter_sql(sql)
        config[:sql_redactors].each do |redactor|
          sql.gsub!(redactor.search, redactor.replace)
        end

        sql
      end
    end
  end
end
