RSpec.describe "End to End" do
  include WaitForPop

  let(:tmp_dir) { Dir.mktmpdir }
  after { FileUtils.remove_entry(tmp_dir) }

  let(:log_path) { "#{tmp_dir}/test_tag.log" }
  let(:log_data) { File.read(log_path) }

  let(:log_hash) do
    hash = {}
    log_data.split("\n").each do |line|
      sha = line.split("|", 2).last
      hash[sha] ||= 0
      hash[sha] += 1
    end
    hash
  end

  let(:log_reverse_hash) do
    Hash[log_hash.map(&:reverse)]
  end

  let(:log_def_path) { "#{tmp_dir}/test_tag_definitions.log" }
  let(:log_def_data) { File.read(log_def_path) }
  let(:log_def_hash) do
    hash = {}
    log_def_data.split("\n").each do |line|
      sha, event = line.split("|", 2)
      hash[sha] = JSON.parse(event)
    end

    hash
  end

  before do
    ActiveRecord::SqlAnalyzer.configure do |c|
      c.logger_root_path tmp_dir
      c.log_sample_proc Proc.new { |_name| true }

      c.add_analyzer(
        name: :test_tag,
        tables: %w(matching_table)
      )
    end

    ActiveRecord::SqlAnalyzer.config[:analyzers].each do |analyzer|
      analyzer[:logger_instance].definition_log_file.sync = true
      analyzer[:logger_instance].log_file.sync = true
    end
  end

  def execute(sql)
    DBConnection.connection.execute(sql)
    wait_for_pop
  end

  def transaction
    DBConnection.connection.transaction { yield }
    wait_for_pop
  end

  it "does not log with a non-matching table" do
    execute "SELECT * FROM nonmatching_table"

    expect(log_data).to eq("")
    expect(log_def_data).to eq("")
  end

  it "logs with a matching + non-matching table in one query" do
    execute "SELECT nmt.id FROM nonmatching_table AS nmt JOIN matching_table AS mt ON mt.id = nmt.id WHERE mt.id = 1234"
    execute "SELECT nmt.id FROM nonmatching_table AS nmt JOIN matching_table AS mt ON mt.id = nmt.id WHERE mt.id = 4321"
    execute "SELECT nmt.id FROM nonmatching_table AS nmt JOIN matching_table AS mt ON mt.id = nmt.id WHERE mt.test_string = 'abc'"

    expect(log_hash.length).to eq(2)

    id_sha = log_reverse_hash[2]
    str_sha = log_reverse_hash[1]

    expect(log_def_hash.length).to eq(2)

    expect(log_def_hash[id_sha]["sql"]).to include("mt.id = '[REDACTED]'")
    expect(log_def_hash[str_sha]["sql"]).to include("mt.test_string = '[REDACTED]'")
  end

  it "logs with only a matching table in a query" do
    execute "SELECT * FROM matching_table WHERE id = 1234"
    execute "SELECT * FROM matching_table WHERE id = 4321"
    execute "SELECT * FROM matching_table WHERE test_string = 'abc'"

    expect(log_hash.length).to eq(2)

    id_sha = log_reverse_hash[2]
    str_sha = log_reverse_hash[1]

    expect(log_def_hash.length).to eq(2)

    expect(log_def_hash[id_sha]["sql"]).to include("id = '[REDACTED]'")
    expect(log_def_hash[str_sha]["sql"]).to include("test_string = '[REDACTED]'")
  end

  it "handles invalid UTF-8" do
    execute "SELECT * FROM matching_table WHERE test_string = '\xe5'"
    execute "SELECT * FROM matching_table WHERE test_string = 'foobar'"

    expect(log_reverse_hash.first.first).to eq(2)

    sha = log_reverse_hash[2]
    expect(log_def_hash[sha]["sql"]).to include("test_string = '[REDACTED]'")
  end

  it "logs multiple queries in a transaction correctly" do
    transaction do
      execute "SELECT * FROM matching_table WHERE id = 4321"
      execute "SELECT * FROM matching_table WHERE test_string = 'abc'"
    end

    2.times do
      transaction do
        execute "SELECT * FROM matching_table WHERE test_string = 'abc'"
        execute "SELECT * FROM matching_table WHERE id = 4321"
      end
    end

    transaction_executed_once_sha = log_reverse_hash[1]
    transaction_executed_twice_sha = log_reverse_hash[2]

    expect(log_def_hash[transaction_executed_once_sha]["sql"]).to eq(
      "BEGIN; " \
      "SELECT * FROM matching_table WHERE id = '[REDACTED]'; " \
      "SELECT * FROM matching_table WHERE test_string = '[REDACTED]'; " \
      "COMMIT;")

    expect(log_def_hash[transaction_executed_twice_sha]["sql"]).to eq(
     "BEGIN; " \
     "SELECT * FROM matching_table WHERE test_string = '[REDACTED]'; " \
     "SELECT * FROM matching_table WHERE id = '[REDACTED]'; " \
     "COMMIT;")
  end

  it "Logs nested transactions correctly" do
    transaction do
      execute "SELECT * FROM matching_table WHERE id = 4321"
      transaction do
        execute "SELECT * FROM matching_table WHERE test_string = 'abc'"
      end
    end

    transaction_executed_once_sha = log_reverse_hash[1]
    expect(log_def_hash[transaction_executed_once_sha]["sql"]).to eq(
        "BEGIN; " \
        "SELECT * FROM matching_table WHERE id = '[REDACTED]'; " \
        "SELECT * FROM matching_table WHERE test_string = '[REDACTED]'; " \
        "COMMIT;")
  end

  it "Logs transactions with inserts correctly" do
    transaction do
      execute "INSERT INTO matching_table (test_string) VALUES ('test_value')"
      execute "SELECT * FROM matching_table WHERE id = 4321"
    end

    transaction_executed_once_sha = log_reverse_hash[1]
    expect(log_def_hash[transaction_executed_once_sha]["sql"]).to eq(
          "BEGIN; " \
            "INSERT INTO matching_table (REDACTED_COLUMNS) VALUES ('[REDACTED]'); " \
            "SELECT * FROM matching_table WHERE id = '[REDACTED]'; " \
            "COMMIT;")
  end

  it "Logs mixed matching-nonmatching selects correctly" do
    transaction do
      execute "SELECT * FROM matching_table WHERE id = 4321"
      execute "SELECT * FROM nonmatching_table WHERE id = 4321"
    end

    transaction_executed_once_sha = log_reverse_hash[1]

    expect(log_def_hash[transaction_executed_once_sha]["sql"]).to eq(
      "BEGIN; " \
      "SELECT * FROM matching_table WHERE id = '[REDACTED]'; " \
      "COMMIT;")
  end

  it "Logs transaction with repeated selects correctly" do
    transaction do
      execute "SELECT * FROM matching_table WHERE id = 4321"
      ['blah', 'bloo'].each do |s|
        execute "SELECT * FROM matching_table WHERE test_string = '#{s}'"
      end
    end

    transaction_executed_once_sha = log_reverse_hash[1]

    expect(log_def_hash[transaction_executed_once_sha]["sql"]).to eq(
                                                                    "BEGIN; " \
      "SELECT * FROM matching_table WHERE id = '[REDACTED]'; " \
      "SELECT * FROM matching_table WHERE test_string = '[REDACTED]'; " \
      "COMMIT;")
  end

  it "Logs transaction with repeated inserts correctly" do
    transaction do
      execute "SELECT * FROM matching_table WHERE id = 4321"
      2.times do
        execute "INSERT INTO matching_table (test_string) VALUES ('test_value')"
      end
    end

    transaction_executed_once_sha = log_reverse_hash[1]

    expect(log_def_hash[transaction_executed_once_sha]["sql"]).to eq(
                                                                    "BEGIN; " \
      "SELECT * FROM matching_table WHERE id = '[REDACTED]'; " \
      "INSERT INTO matching_table (REDACTED_COLUMNS) VALUES ('[REDACTED]'); " \
      "COMMIT;")
  end


  it "Logs mixed matching-nonmatching with inserts correctly" do
    transaction do
      execute "SELECT * FROM matching_table WHERE id = 4321"
      execute "INSERT INTO nonmatching_table (id) VALUES (1)"
    end

    transaction_executed_once_sha = log_reverse_hash[1]

    expect(log_def_hash[transaction_executed_once_sha]["sql"]).to eq(
                                                                    "BEGIN; " \
      "SELECT * FROM matching_table WHERE id = '[REDACTED]'; " \
      "INSERT INTO nonmatching_table (REDACTED_COLUMNS) VALUES ('[REDACTED]'); " \
      "COMMIT;")
  end

  it "Does not log nonmatching-only queries" do
    transaction do
      execute "SELECT * FROM nonmatching_table WHERE id = 4321"
      execute "SELECT * FROM nonmatching_table WHERE id = 4321"
    end

    expect(log_def_hash.size).to eq(0)
  end

  context "Selectively sampling" do
    before do
      ActiveRecord::SqlAnalyzer.configure do |c|
        times_called = 0
        # Return true every other call, starting with the first call
        c.log_sample_proc Proc.new { |_name| (times_called += 1) % 2 == 1 }
      end
    end

    it "Samples some but not other selects" do
      execute "SELECT * FROM matching_table WHERE id = 1"
      execute "SELECT * FROM matching_table WHERE test_string = 'abc'"

      expect(log_def_hash.size).to eq(1)
      expect(log_def_hash.map { |_hash, query| query['sql'] }).to eq([
        "SELECT * FROM matching_table WHERE id = '[REDACTED]'"])
    end

    it "Samples some but not other whole transactions" do
      transaction do
        execute "SELECT * FROM matching_table WHERE id = 1"
        execute "SELECT * FROM matching_table WHERE test_string = 'abc'"
      end

      transaction do
        execute "SELECT * FROM matching_table WHERE id = 1 and test_string = 'abc'"
        execute "SELECT * FROM matching_table WHERE id > 4 and id < 8"
      end


      transaction_executed_once_sha = log_reverse_hash[1]

      expect(log_def_hash.size).to eq(1)
      expect(log_def_hash[transaction_executed_once_sha]["sql"]).to eq(
        "BEGIN; " \
        "SELECT * FROM matching_table WHERE id = '[REDACTED]'; " \
        "SELECT * FROM matching_table WHERE test_string = '[REDACTED]'; " \
        "COMMIT;")
    end
  end

  context "when sampling is disabled" do
    before do
      ActiveRecord::SqlAnalyzer.configure do |c|
        c.log_sample_proc Proc.new { |_name| false }
      end
    end

    it "does not log" do
      execute "SELECT * FROM matching_table"

      expect(log_data).to eq("")
      expect(log_def_data).to eq("")
    end
  end
end
