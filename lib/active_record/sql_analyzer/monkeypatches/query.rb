
module ActiveRecord
  module SqlAnalyzer
    module Monkeypatches
      module Query
        def execute(sql, *args)
          return super unless SqlAnalyzer.config

          safe_sql = nil

          SqlAnalyzer.config[:analyzers].each do |analyzer|
            if SqlAnalyzer.config[:should_log_sample_proc].call(analyzer[:name])
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
                  request_path: Thread.current[:_ar_analyzer_request_path]
                }
              end
            end
          end

          super
        end
      end
    end
  end
end
