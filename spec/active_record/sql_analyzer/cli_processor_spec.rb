require_relative "../../../lib/active_record/sql_analyzer/cli_processor"

RSpec.describe ActiveRecord::SqlAnalyzer::CLIProcessor do
  let(:tmp_dir) { Dir.mktmpdir }
  after { FileUtils.remove_entry(tmp_dir) }

  def write_logs(prefix, *events)
    started_at = Time.utc(2015, 1, 1, 0)

    events.each_slice(2).each_with_index do |lines, index|
      logger = ActiveRecord::SqlAnalyzer::CompactLogger.new(
        tmp_dir,
        "#{prefix}_#{index}"
      )

      lines.each do |event|
        started_at += 3600

        Timecop.freeze(started_at) do
          logger.log(event)
        end
      end

      logger.close
    end
  end

  let(:instance) { described_class.new(2) }

  before do
    write_logs(:foo,
               { sql: "F-SQL1", caller: "CALLER1", tag: true },
               { sql: "F-SQL2", caller: "CALLER2", tag: true },
               { sql: "F-SQL1", caller: "CALLER1", tag: true },
               { sql: "F-SQL3", caller: "CALLER3", tag: true },
               { sql: "F-SQL2", caller: "CALLER2", tag: true })

    write_logs(:bar,
               { sql: "B-SQL1", caller: "CALLER1" },
               { sql: "B-SQL2", caller: "CALLER2" },
               { sql: "B-SQL3", caller: "CALLER3" },
               { sql: "B-SQL2", caller: "CALLER2" },
               { sql: "B-SQL1", caller: "CALLER1" })
  end

  subject(:process) do
    instance.run_definition(
      Dir["#{tmp_dir}/*_*_definitions.log"].map do |path|
        [File.basename(path).split("_", 2).first, path]
      end
    )

    instance.run_usage(
      Dir["#{tmp_dir}/*_*.log"].map do |path|
        next if path =~ /definitions\.log$/
        [File.basename(path).split("_", 2).first, path]
      end.compact
    )

    instance.definitions
  end

  it "processes logs" do
    logs = process

    expect(logs["foo"].length).to eq(3)

    queries = logs["foo"].values.sort_by { |row| row["sql"] }

    expect(queries[0]["sql"]).to eq("F-SQL1")
    expect(queries[0]["caller"]).to eq("CALLER1")
    expect(queries[0]["count"]).to eq(2)
    expect(queries[0]["last_called"]).to eq(Time.utc(2015, 1, 1, 3))
    expect(queries[0]["tag"]).to eq(true)

    expect(queries[1]["sql"]).to eq("F-SQL2")
    expect(queries[1]["caller"]).to eq("CALLER2")
    expect(queries[1]["count"]).to eq(2)
    expect(queries[1]["last_called"]).to eq(Time.utc(2015, 1, 1, 5))
    expect(queries[1]["tag"]).to eq(true)

    expect(queries[2]["sql"]).to eq("F-SQL3")
    expect(queries[2]["caller"]).to eq("CALLER3")
    expect(queries[2]["count"]).to eq(1)
    expect(queries[2]["last_called"]).to eq(Time.utc(2015, 1, 1, 4))
    expect(queries[2]["tag"]).to eq(true)

    expect(logs["bar"].length).to eq(3)

    queries = logs["bar"].values.sort_by { |row| row["sql"] }

    expect(queries[0]["sql"]).to eq("B-SQL1")
    expect(queries[0]["caller"]).to eq("CALLER1")
    expect(queries[0]["count"]).to eq(2)
    expect(queries[0]["last_called"]).to eq(Time.utc(2015, 1, 1, 5))
    expect(queries[0]["tag"]).to eq(nil)

    expect(queries[1]["sql"]).to eq("B-SQL2")
    expect(queries[1]["caller"]).to eq("CALLER2")
    expect(queries[1]["count"]).to eq(2)
    expect(queries[1]["last_called"]).to eq(Time.utc(2015, 1, 1, 4))
    expect(queries[1]["tag"]).to eq(nil)

    expect(queries[2]["sql"]).to eq("B-SQL3")
    expect(queries[2]["caller"]).to eq("CALLER3")
    expect(queries[2]["count"]).to eq(1)
    expect(queries[2]["last_called"]).to eq(Time.utc(2015, 1, 1, 3))
    expect(queries[2]["tag"]).to eq(nil)
  end

  it "dumps to disk" do
    process
    instance.dump(tmp_dir)

    paths = Dir["#{tmp_dir}/{foo,bar}_#{Time.now.strftime("%Y-%m-%d")}.log"]
    expect(paths.length).to eq(2)
  end
end
