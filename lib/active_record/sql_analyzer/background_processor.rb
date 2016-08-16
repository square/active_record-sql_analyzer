require "set"

module ActiveRecord
  module SqlAnalyzer
    class BackgroundProcessor
      def initialize
        @queue = Queue.new
      end

      def <<(event)
        processor_thread
        @queue << event
      end

      private

      MUTEX = Mutex.new

      def process_queue
        event = @queue.pop

        event[:calls] = event[:calls].map do |call|
          {
            caller: SqlAnalyzer.config[:backtrace_filter_proc].call(call[:caller]),
            sql: SqlAnalyzer.config[:sql_redactor_complex_proc].call(call[:sql].dup)
          }
        end

        logger = event.delete(:logger)
        logger.filter_event(event)
        logger.log(event)
      end

      def processor_thread
        # Avoid grabbing a mutex unless we really need to
        return if @thread && @thread.alive?

        MUTEX.synchronize do
          # Double check to avoid a race condition
          return if @thread && @thread.alive?

          @thread = Thread.new do
            Rails.logger.info "[SQL-Analyzer] Starting background query thread id #{Thread.current.object_id} in pid #{Process.pid}"

            begin
              loop do
                process_queue
              end
            rescue => ex
              Rails.logger.warn "[SQL-Analyzer] Exception in thread #{Thread.current.object_id}: #{ex.class}, #{ex.message}"
              Rails.logger.warn "[SQL-Analyzer] #{ex.backtrace.join(", ")}"
            end
          end
        end
      end
    end
  end
end
