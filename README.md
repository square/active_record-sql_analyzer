# ActiveRecord SQL Analyzer

[![Build Status](https://travis-ci.org/square/active_record-sql_analyzer.svg?branch=master)](https://travis-ci.org/square/active_record-sql_analyzer)

This gem provides a hook into ActiveRecord to redact, sample, and aggregate SQL queries being ran against production systems. It gives you better visibility into exactly what kind of queries are being run, and aids in planning pulling features out of your service.

Currently this only supports MySQL. It should have no problems working with other SQL drivers, but we've only tested the redaction on MySQL. 

## Warning!

This does log raw SQL to disk (by default). While we've been using this with the regexes below for redaction + a redactor gem, you should ensure you will not inadvertently log data to disk you do not want to. You can also take a look at [Custom Loggers](#custom-loggers) to log somewhere else.

## Usage

By default, you only really need to configure what you want to analyze, and the sample rate. To get started quickly:

```ruby
ActiveRecord::SqlAnalyzer.configure do |c|
  c.add_analyzer do |a|
    a.name 'users'
    a.tables %w(users permissions)
  end
  
  c.log_sample_proc Proc.new { |name| rand(1..100) <= 25 }
end
```

Will sample 25% of the queries against the `users` and `permissions` tables (including JOINs that use either), to `Rails.root.join('log', 'users.log')` and `Rails.root.join('log', 'users_definitions.log')`.

## Analyzer

You can use the `ar-log-analyzer` command to analyze the created log files. It will output an aggregated JSON dump with SQL, backtraces, call counts and when it was last used.

## Aggregation

Queries are aggregated based on the redacted SQL string + first line of the stacktrace. You can tweak the redaction used for SQL/backtrace to improve the aggregation.

If a callsite is listed as ambiguous, we automatically include a couple more lines of the stacktrace. See [Advanced Configuration](#advanced-configuration) for more information.

## Custom Loggers

By default, the analyze is logged to disk. You can create your own logger class and send logs to somewhere like a SQL DB instead. Take a look at `ActiveRecord::SqlAnalyzer::RedactedLogger`, `ActiveRecord::SqlAnalyzer::CompactLogger`, and `ActiveRecord::SqlAnalyzer::Logger` as an example of how to build your own.

## Advanced Configuration

```ruby
  ActiveRecord::SqlAnalyzer.configure do |c|
    # Define a custom backtrace filter. In this case, only filter out lines containing `/nokogiri/`
    c.backtrace_filter_proc Proc.new { |lines|
      lines.reject { |line| line =~ /\/nokogiri\// }
    }
  
    # Add a new analyzer, can add as many as you need
    c.add_analyzer(
      # Used for the prefix of the log files, as well as passed to `log_sample_proc`
      name: 'users'
      # SQL table names to log
      tables: %w(users permissions)
      # Logger to use (Can be changed to use your own custom one)
      logger: ActiveRecord::SqlAnalyzer::RedactedLogger
    )
    
    # Directory to log to, by default this is `Rails.root.join('log')`
    c.logger_root_path '/tmp/'
    
    # Sets a new sampler, logs only 25% of queries tagged with `users` and 50% tagged with `payments`
    c.log_sample_proc Proc.new { |name|
      val = rand(1..100)
      
      if name == 'users'
        val <= 25
      elsif name == 'payments'
        val <= 50
      end
    }
    
    # Beyond the simple find/replace, any kind of dynamic redaction you need.
    # We use this with another gem that redacts common patterns like phone numbers or emails.
    c.complex_sql_redactor_proc Proc.new { |sql|
      sql.gsub!(/(.+)@(.+)\.(.+)/, "")
    }
    
    # Adds a new redactor that strips out all numbers
    c.add_sql_redactors [
      [/[0-9]+/, ""] 
    ]
    
    # Adds a redactor for backtraces to improve aggregation.
    # In this case, strips out line numbers in case your code changes day to day.
    c.add_backtrace_redactors [
      [/:([0-9]+):in/, ":in"]
    ]
    
    # Any backtraces matching the regexes will switch to an ambiguous tracer
    # where we log more details. Can be handy if you have code sites that
    # inherits from other files or middlewares that are showing up in the caller.
    c.add_ambiguous_tracers [
      %r{\Aapp/middleware/query_string_sanitizer\.rb:\d+:in `call'\z}
    ]
    
    # How many additional lines to log when calls are ambiguous
    c.ambiguous_backtrace_lines 5
  end
```


## License

Copyright 2015 Square Inc.
 
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
 
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
