require "rspec"
require "active_record"
require "timecop"
require "tmpdir"
require "support/db_connection"
require "support/stub_rails"
require "support/wait_for_pop"
require "active_record/sql_analyzer.rb"

DBConnection.setup_db
ActiveRecord::SqlAnalyzer.install!

RSpec.configure do |c|
  c.disable_monkey_patching!

  c.before :each do
    DBConnection.reset
  end

  c.after :each do
    # Try and reset our state to something a bit fresher
    if ActiveRecord::SqlAnalyzer.config
      thread = ActiveRecord::SqlAnalyzer.background_processor.instance_variable_get(:@thread)
      thread.terminate if thread

      ActiveRecord::SqlAnalyzer.config[:analyzers].each do |analyzer|
        analyzer[:logger_instance].close
      end

      ActiveRecord::SqlAnalyzer.instance_variable_set(:@background_processor, nil)
      ActiveRecord::SqlAnalyzer.instance_variable_set(:@config, nil)
    end
  end
end
