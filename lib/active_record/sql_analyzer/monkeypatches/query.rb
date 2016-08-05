require 'securerandom'

module ActiveRecord
  module SqlAnalyzer
    module Monkeypatches
      module Query
        def execute(sql, *args)
          return super unless SqlAnalyzer.config

          safe_sql = nil

          SqlAnalyzer.config[:analyzers].each do |analyzer|
            if _query_analyzer_private_should_sample_query(analyzer[:name])
              # This is here rather than above intentionally.
              # We assume we're not going to be analyzing 100% of queries and want to only re-encode
              # when it's actually relevant.
              safe_sql ||= sql.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)

              if safe_sql =~ analyzer[:table_regex]
                SqlAnalyzer.background_processor << {
                  sql: safe_sql,
                  caller: caller,
                  logger: analyzer[:logger_instance],
                  tag: Thread.current[:_ar_analyzer_tag],
                  request_path: Thread.current[:_ar_analyzer_request_path],
                  transaction: @_query_analyzer_private_transaction_uuid
                }
              end
            end
          end

          super
        end

        # Whether or not we should sample the query. If it's part of a transaction, check whether we
        # are sampling the transaction. Otherwise, run the sample proc.
        def _query_analyzer_private_should_sample_query(analyzer_name)
          if @_query_analyzer_private_transaction_uuid.present?
            @_query_analyzer_private_should_sample_transaction[analyzer_name]
          else
            SqlAnalyzer.config[:should_log_sample_proc].call(analyzer_name)
          end
        end

        # Calculate hash of analyzer_name -> boolean representing whether we should sample the
        # whole transaction for this analyzer.
        def _query_analyzer_private_calculate_sampling_for_all_analyzers
          SqlAnalyzer.config[:analyzers].map do |analyzer|
            [analyzer[:name], SqlAnalyzer.config[:should_log_sample_proc].call(analyzer[:name])]
          end.to_h
        end

        def transaction(requires_new: nil, isolation: nil, joinable: true)
          must_clear_uuid = false

          if @_query_analyzer_private_transaction_uuid.nil? then
            must_clear_uuid = true
            @_query_analyzer_private_transaction_uuid = SecureRandom.uuid
            @_query_analyzer_private_should_sample_transaction =
               _query_analyzer_private_calculate_sampling_for_all_analyzers
          end

          super
        ensure
          if must_clear_uuid
            @_query_analyzer_private_transaction_uuid = nil
            @_query_analyzer_private_should_sample_transaction = nil
          end
        end
      end
    end
  end
end
