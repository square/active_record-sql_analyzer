require 'securerandom'

module ActiveRecord
  module SqlAnalyzer
    module Monkeypatches
      module Query
        QueryAnalyzerCall = Struct.new(:sql, :caller)

        def execute(sql, *args)
          return super unless SqlAnalyzer.config

          if @_query_analyzer_private_transaction_queue
            @_query_analyzer_private_transaction_queue << QueryAnalyzerCall.new(sql, caller)
          else
            safe_sql = nil

            SqlAnalyzer.config[:analyzers].each do |analyzer|
              if SqlAnalyzer.config[:should_log_sample_proc].call(analyzer[:name])
                # This is here rather than above intentionally.
                # We assume we're not going to be analyzing 100% of queries and want to only re-encode
                # when it's actually relevant.
                safe_sql ||= sql.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)

                if safe_sql =~ analyzer[:table_regex]
                  SqlAnalyzer.background_processor <<
                    _query_analyzer_private_query_stanza([QueryAnalyzerCall.new(safe_sql, caller)], analyzer)
                end
              end
            end
          end

          super
        end

        # Drain the transaction query queue. Log the current transaction out to any logger that samples it.
        def _query_analyzer_private_drain_transaction_queue
          reencoded_calls = nil

          SqlAnalyzer.config[:analyzers].each do |analyzer|
            if SqlAnalyzer.config[:should_log_sample_proc].call(analyzer[:name])
              # Again, trying to only re-encode and join strings if the transaction is actually
              # sampled.
              reencoded_calls ||= @_query_analyzer_private_transaction_queue.map do |call|
                QueryAnalyzerCall.new(call.sql.encode(Encoding::UTF_8, invalid: :replace, undef: :replace), call.caller)
              end

              matching_calls = reencoded_calls.select do |call|
                (call.sql =~ /^(UPDATE|INSERT|DELETE)/) || (call.sql =~ analyzer[:table_regex])
              end

              if matching_calls.any?
                # Add back in the begin and commit statements, using the correct call stack references
                if reencoded_calls.first.sql == 'BEGIN'
                  matching_calls.unshift(reencoded_calls.first)
                end

                if ['COMMIT', 'ROLLBACK'].include? reencoded_calls.last.sql
                  matching_calls << reencoded_calls.last
                end

                SqlAnalyzer.background_processor <<
                  _query_analyzer_private_query_stanza(matching_calls, analyzer)
              end
            end
          end
        end

        # Helper method to construct the event for a query or transaction.
        # safe_sql [string]: SQL statement or combined SQL statement for transaction
        # calls: A list of QueryAnalyzerCall objects to be turned into call hashes
        def _query_analyzer_private_query_stanza(calls, analyzer)
          {
            # Calls are of the format {sql: String, caller: String}
            calls: calls.map(&:to_h),
            logger: analyzer[:logger_instance],
            tag: Thread.current[:_ar_analyzer_tag],
            request_path: Thread.current[:_ar_analyzer_request_path],
          }
        end

        def transaction(requires_new: nil, isolation: nil, joinable: true)
          must_clear_transaction = false

          if SqlAnalyzer.config[:consolidate_transactions]
            if @_query_analyzer_private_transaction_queue.nil?
              must_clear_transaction = true
              @_query_analyzer_private_transaction_queue = []
            end
          end

          super
        ensure
          if must_clear_transaction
            _query_analyzer_private_drain_transaction_queue
            @_query_analyzer_private_transaction_queue = nil
          end
        end
      end
    end
  end
end
