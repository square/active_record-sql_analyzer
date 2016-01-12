RSpec.describe ActiveRecord::SqlAnalyzer::Analyzer do
  let(:analyzer) do
    described_class.new.tap do |instance|
      instance.tables %w(foo bar)
    end
  end

  context "table regex" do
    let(:regex) { analyzer[:table_regex] }

    it "matches" do
      expect("SELECT * FROM foo").to match(regex)
      expect("DELETE FROM foo").to match(regex)
      expect("INSERT INTO bar (a, b, c) VALUES (1, 2, 3)").to match(regex)
      expect("UPDATE bar SET a=b WHERE id=1").to match(regex)
    end

    it "matches with complex queries" do
      expect("SELECT * FROM apple JOIN foo").to match(regex)
      expect("SELECT * FROM apple LEFT JOIN foo").to match(regex)
      expect("SELECT * FROM apple WHERE id = (SELECT * FROM foo)").to match(regex)
    end

    it "does not match" do
      expect("SELECT * FROM apple WHERE id='foo'").to_not match(regex)
      expect("SELECT foo FROM apple WHERE id='bar'").to_not match(regex)

      expect("DELETE FROM apple").to_not match(regex)
      expect("INSERT INTO apple (a, b, c) VALUES (1, 2, 3)").to_not match(regex)
      expect("UPDATE apple SET a=b WHERE id=1").to_not match(regex)
    end
  end
end
