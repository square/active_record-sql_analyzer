RSpec.describe ActiveRecord::SqlAnalyzer::BackgroundProcessor do
  include WaitForPop

  let(:instance) { described_class.new }

  let(:event) { {caller: "CALLER", sql: "SQL", logger: logger} }

  let(:logger) do
    Class.new do
      def self.events
        @events ||= []
      end

      def self.filter_event(*)
      end

      def self.log(event)
        events << event
        sleep 2
      end
    end
  end

  before do
    ActiveRecord::SqlAnalyzer.configure do |c|
      c.backtrace_filter_proc Proc.new { |lines| "BFP #{lines}" }
      c.complex_sql_redactor_proc Proc.new { |sql| "CSRP #{sql}" }
    end
  end

  it "processes in the background" do
    instance << event
    wait_for_pop

    expect(logger.events).to eq(
      [
        {
          caller: "BFP CALLER",
          sql: "CSRP SQL"
        }
      ]
    )
  end
end
