require 'securerandom'

module ActiveRecord
  module SqlAnalyzer
    module Monkeypatches
      module Query
        QueryAnalyzerCall = Struct.new(:sql, :caller)

        execute_method = if ActiveRecord.version >= Gem::Version.new('7.0')
          :raw_execute
        else
          :execute
        end
        define_method(execute_method) do |sql, *args|
          return super(sql, args) unless SqlAnalyzer.config
          safe_sql = nil
          query_analyzer_call = nil

          # Starting with activerecord v6, transaction materialization is
          # deferred until just before query execution, and so
          # begin_db_transaction is now called inside the `super` call here.
          begin
            super(sql, args)
          ensure
            # Record "full" transactions (see below for more information about "full")
            if @_query_analyzer_private_in_transaction
              if @_query_analyzer_private_record_transaction
                safe_sql ||= sql.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
                query_analyzer_call ||= QueryAnalyzerCall.new(safe_sql, caller)
                @_query_analyzer_private_transaction_queue << query_analyzer_call
              end
            end

            # Record interesting queries
            SqlAnalyzer.config[:analyzers].each do |analyzer|
              if SqlAnalyzer.config[:should_log_sample_proc].call(analyzer[:name])
                # This is here rather than above intentionally.
                # We assume we're not going to be analyzing 100% of queries and want to only re-encode
                # when it's actually relevant.
                safe_sql ||= sql.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
                query_analyzer_call ||= QueryAnalyzerCall.new(safe_sql, caller)

                if safe_sql =~ analyzer[:table_regex]
                  SqlAnalyzer.background_processor <<
                    _query_analyzer_private_query_stanza([query_analyzer_call], analyzer)
                end
              end
            end
          end
        end

        def begin_db_transaction
          @_query_analyzer_private_in_transaction = true

          record_transaction = SqlAnalyzer.config[:analyzers].any? do |analyzer|
            SqlAnalyzer.config[:should_log_sample_proc].call(analyzer[:name])
          end
          if record_transaction
            @_query_analyzer_private_transaction_queue ||= []
            @_query_analyzer_private_record_transaction = true
          else
            @_query_analyzer_private_record_transaction = nil
          end
          super
        end

        def commit_db_transaction
          _query_analyzer_private_drain_transaction_queue("COMMIT")
          super
        ensure
          @_query_analyzer_private_in_transaction = false
        end

        def exec_rollback_db_transaction
          _query_analyzer_private_drain_transaction_queue("ROLLBACK")
          super
        ensure
          @_query_analyzer_private_in_transaction = false
        end

        # "private" methods for this monkeypatch

        # Drain the transaction query queue. Log the current transaction out to any logger that samples it.
        def _query_analyzer_private_drain_transaction_queue(last_query)
          return unless @_query_analyzer_private_record_transaction

          reencoded_calls = nil

          SqlAnalyzer.config[:analyzers].each do |analyzer|
            reencoded_calls ||= @_query_analyzer_private_transaction_queue << QueryAnalyzerCall.new(last_query, caller)

            has_matching_calls = reencoded_calls.any? { |call| call.sql =~ analyzer[:table_regex] }

            # Record "full" transactions
            # Record all INSERT, UPDATE, and DELETE
            # Record all queries that match the analyzer's table_regex
            if has_matching_calls
              matching_calls = reencoded_calls.select do |call|
                (call.sql =~ /^(BEGIN|COMMIT|ROLLBACK|UPDATE|INSERT|DELETE)/) || (call.sql =~ analyzer[:table_regex])
              end

              SqlAnalyzer.background_processor << _query_analyzer_private_query_stanza(matching_calls, analyzer)
            end
          end

          @_query_analyzer_private_transaction_queue.clear
          @_query_analyzer_private_record_transaction = nil
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
      end
    end
  end
end
