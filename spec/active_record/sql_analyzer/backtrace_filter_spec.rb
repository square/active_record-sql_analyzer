RSpec.describe ActiveRecord::SqlAnalyzer::BacktraceFilter do
  before do
    ActiveRecord::SqlAnalyzer.configure { |_c| }
  end

  it "filters non-app paths" do
    lines = ActiveRecord::SqlAnalyzer.config[:backtrace_filter_proc].call(
      [
        "foo/bar:1 in 'method'",
        "#{Gem.path.first}:4231 in 'method'",
        "foo/bar:2 in 'method'",
        "#{File.realpath(Gem.path.first)}:9531 in 'method'",
        "foo/bar:3 in 'method'",
        "(eval):1234 in 'method'",
        "foo/bar:4 in 'method'"
      ]
    )

    expect(lines).to eq(
      [
        "foo/bar:1 in 'method'",
        "foo/bar:2 in 'method'",
        "foo/bar:3 in 'method'",
        "foo/bar:4 in 'method'"
      ]
    )
  end
end
