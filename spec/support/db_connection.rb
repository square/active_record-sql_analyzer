class DBConnection
  def self.db
    @db ||= ActiveRecord::Base.establish_connection(
      configuration.merge(database: 'ar_sql_analyzer_test')
    )
  end

  def self.connection
    db.connection
  end

  def self.configuration
    {
      adapter: 'mysql2',
      host: 'localhost',
      encoding: 'utf8',
      usernamme: ENV["TRAVIS"] ? "travis" : "root"
    }
  end

  def self.setup_db
    ActiveRecord::Base.raise_in_transactional_callbacks = true
    conn = ActiveRecord::Base.establish_connection(configuration)
    conn.connection.execute <<-SQL
      CREATE DATABASE IF NOT EXISTS ar_sql_analyzer_test
    SQL
  end

  def self.reset
    connection.execute <<-SQL
      DROP TABLE IF EXISTS matching_table
    SQL

    connection.execute <<-SQL
      CREATE TABLE `matching_table` (
        `id` int(11) NOT NULL AUTO_INCREMENT,
        `test_string` varchar(255) DEFAULT NULL,
        PRIMARY KEY (`id`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8
    SQL

    connection.execute <<-SQL
      DROP TABLE IF EXISTS second_matching_table
    SQL

    connection.execute <<-SQL
      CREATE TABLE `second_matching_table` (
        `id` int(11) NOT NULL AUTO_INCREMENT,
        `test_string` varchar(255) DEFAULT NULL,
        PRIMARY KEY (`id`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8
    SQL

    connection.execute <<-SQL
      DROP TABLE IF EXISTS nonmatching_table
    SQL

    connection.execute <<-SQL
      CREATE TABLE `nonmatching_table` (
        `id` int(11) NOT NULL AUTO_INCREMENT,
        `test_string` varchar(255) DEFAULT NULL,
        PRIMARY KEY (`id`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8
    SQL
  end
end
