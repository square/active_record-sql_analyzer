RSpec.describe ActiveRecord::SqlAnalyzer::RedactedLogger do
  let(:tmp_dir) { Dir.mktmpdir }
  after { FileUtils.remove_entry(tmp_dir) }

  context "#filter_event" do
    let(:event) { {} }

    subject(:filter_event) do
      instance = described_class.new(tmp_dir, "foo")
      instance.filter_event(event)
      event
    end

    before do
      ActiveRecord::SqlAnalyzer.configure do |c|
        c.add_backtrace_redactors [
          [/erb_erb_[0-9]+_[0-9]+/, ""]
        ]
      end
    end

    context "ambiguous backtraces" do
      let(:event) do
        {
          caller: %w(ambiguous foo bar),
          sql: ""
        }
      end

      before do
        ActiveRecord::SqlAnalyzer.configure do |c|
          c.add_ambiguous_tracers [/ambiguous/]
        end
      end

      it "switches to ambiguous backtrace logging" do
        expect(filter_event[:caller]).to eq("ambiguous, foo, bar")
      end
    end

    context "backtrace" do
      let(:event) do
        {
          caller: %w(foo-bar-erb_erb_1_5),
          sql: ""
        }
      end

      it "redacts" do
        expect(filter_event[:caller]).to eq("foo-bar-")
      end
    end

    context "sql" do
      let(:event) do
        {
          caller: [""],
          sql: "SELECT * FROM foo WHERE id = 1234"
        }
      end

      it "redacts" do
        expect(filter_event[:sql]).to eq("SELECT * FROM foo WHERE id = [REDACTED]")
      end
    end
  end
end
