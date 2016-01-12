module WaitForPop
  # This is trying to work around race conditions in a semi-sane manner
  def wait_for_pop
    queue = ActiveRecord::SqlAnalyzer.background_processor.instance_variable_get(:@queue)

    4.times do
      return sleep 0.1 if queue.empty?
      sleep 0.05
    end

    raise "Queue failed to drain in 0.2 seconds"
  end
end
