require "fileutils"
require_relative "../../../lib/active_record/sql_analyzer/cli"
require_relative "../../../lib/active_record/sql_analyzer/cli_processor"

RSpec.describe ActiveRecord::SqlAnalyzer::CLI do
  let(:tmp_dir) { Dir.mktmpdir }
  after { FileUtils.remove_entry(tmp_dir) }

  let(:instance) do
    cli = described_class.new
    cli.parse_options(["--log-dir", tmp_dir, "--dest-dir", tmp_dir])
    cli
  end

  before do
    %w(foo bar).each do |prefix|
      3.times do |i|
        FileUtils.touch("#{tmp_dir}/#{prefix}.log.#{i}")
        FileUtils.touch("#{tmp_dir}/#{prefix}_definitions.log.#{i}")
      end
    end
  end

  it "parses logs and starts the processor" do
    expect(instance.processor).to receive(:run_definition) do |paths|
      expect(paths.length).to eq(6)

      prefixes = paths[0, 3].map(&:first)
      logs = paths[0, 3].map(&:last)
      expect(prefixes.uniq).to eq(["bar"])
      expect(logs).to include(/bar_definitions\.log\.0/)
      expect(logs).to include(/bar_definitions\.log\.1/)
      expect(logs).to include(/bar_definitions\.log\.2/)

      prefixes = paths[3, 6].map(&:first)
      logs = paths[3, 6].map(&:last)
      expect(prefixes.uniq).to eq(["foo"])
      expect(logs).to include(/foo_definitions\.log\.0/)
      expect(logs).to include(/foo_definitions\.log\.1/)
      expect(logs).to include(/foo_definitions\.log\.2/)
    end

    expect(instance.processor).to receive(:run_usage) do |paths|
      expect(paths.length).to eq(6)

      prefixes = paths[0, 3].map(&:first)
      logs = paths[0, 3].map(&:last)
      expect(prefixes.uniq).to eq(["bar"])
      expect(logs).to include(/bar\.log\.0/)
      expect(logs).to include(/bar\.log\.1/)
      expect(logs).to include(/bar\.log\.2/)

      prefixes = paths[3, 6].map(&:first)
      logs = paths[3, 6].map(&:last)
      expect(prefixes.uniq).to eq(["foo"])
      expect(logs).to include(/foo\.log\.0/)
      expect(logs).to include(/foo\.log\.1/)
      expect(logs).to include(/foo\.log\.2/)
    end

    expect(instance.processor).to receive(:dump).with(tmp_dir)

    instance.run
  end
end
