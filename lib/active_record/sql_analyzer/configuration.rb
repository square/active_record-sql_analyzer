module ActiveRecord
  module SqlAnalyzer
    class Configuration
      attr_reader :options

      def initialize
        @options = {}
        setup_defaults
      end

      # Setup a custom proc that filters out lines before passing them to the loggers.
      # By default, this attempts to filter out all non-app code lines.
      def backtrace_filter_proc(proc)
        check_proc(proc, 1, "the backtrace lines")
        @options[:backtrace_filter_proc] = proc
      end

      # Setup a new analyzer for monitoring tables
      #
      # add_analyzer(
      #   name: 'users',
      #   tables: %w(users permissions),
      #   logger: ActiveRecord::SqlAnalyzer::RedactedLogger
      # )
      #
      # Will setup an analyzer that looks at the tables users and permissions
      # when it finds relevant data, it passes it through the `RedactedLogger` class.
      # When calling the proc passed to `log_sample_proc`, it will use the name
      # `users` to help identify it, as well as when logging to disk.
      #
      def add_analyzer(result)
        analyzer = Analyzer.new
        analyzer.name(result[:name])
        analyzer.tables(result[:tables])
        analyzer.logger(result[:logger])
        analyzer.setup

        @options[:analyzers] << analyzer
        analyzer
      end

      # Root path where all logs go.
      # Defaults to `Rails.root.join('log')`
      def logger_root_path(path)
        unless Dir.exist?(path)
          raise ArgumentError, "Path '#{path}' is not a directory"
        end

        @options[:logger_root_path] = path
      end

      # Set a proc that determines whether or not to log a single event.
      # This must be set to log anything, and controls how many SQL queries you look at.
      #
      # Proc.new { |name| true }
      #
      # Will log everything no matter what
      #
      # Proc.new do |name|
      #   rand(1..100) <= 50
      # end
      #
      # Will only log 50% of queries.
      #
      # You can hook this into something like Redis to allow dynamic control of the ratio
      # without having to redeploy/restart your application.
      #
      def log_sample_proc(proc)
        check_proc(proc, 1, "the analyzer name")
        @options[:should_log_sample_proc] = proc
      end

      # For hooking in more complicated redactions beyond a simple find/replace.
      def complex_sql_redactor_proc(proc)
        check_proc(proc, 1, "the SQL statement")
        @options[:sql_redactor_complex_proc] = proc
      end

      # Additional redactors to filter out data in SQL you don't want logged
      def add_sql_redactors(list)
        @options[:sql_redactors].concat(create_redactors(list))
      end

      # Backtrace redactors filter out data in the backtrace
      # useful if you want to get rid of lines numbers
      def add_backtrace_redactors(list)
        @options[:backtrace_redactors].concat(create_redactors(list))
      end

      # If the first line in the backtrace matches the regex given, we switch to
      # ambiguous tracing mode for that call where we log more of the backtrace.
      #
      # As an example, if you find you're only getting middleware, you could use:
      #
      # %r{\Aapp/middleware/query_string_sanitizer\.rb:\d+:in `call'\z}
      #
      # Which would log up to ambiguous_backtrace_lines (default 3) total lines,
      # rather than the default 1.
      def add_ambiguous_tracers(list)
        list.each do |row|
          unless row.is_a?(Regexp)
            raise ArgumentError, "Tracing filters must be a Regexp to match on"
          end
        end

        @options[:ambiguous_tracers].concat(list)
      end

      # How many total lines to log when the caller is ambiguous
      def ambiguous_backtrace_lines(lines)
        if !lines.is_a?(Fixnum)
          raise ArgumentError, "Lines must be a Fixnum"
        elsif lines <= 1
          raise ArgumentError, "Lines cannot be <= 1"
        end

        @options[:ambiguous_backtrace_lines] = lines
      end

      def [](key)
        @options[key]
      end

      private

      def check_proc(proc, arity, msg)
        if !proc.is_a?(Proc)
          raise ArgumentError, "You must pass a proc"
        elsif proc.arity != 1
          raise ArgumentError, "Proc must accept 1 argument for #{msg}"
        end
      end

      def create_redactors(list)
        list.map do |redact|
          if redact.length != 2
            raise ArgumentError, "Redactor row should only have two entries"
          elsif !redact.first.is_a?(Regexp)
            raise ArgumentError, "First value in pair must be a Regexp to match on"
          elsif !redact.last.is_a?(String)
            raise ArgumentError, "Last value in pair must be a String to replace with"
          end

          Redactor.new(*redact)
        end
      end

      def setup_defaults
        quotedValuePattern = %{('([^\\\\']|\\\\.|'')*'|"([^\\\\"]|\\\\.|"")*")}
        @options[:sql_redactors] = [
          Redactor.new(/\n/, " "),
          Redactor.new(/\s+/, " "),
          Redactor.new(/IN \([^)]+\)/i, "IN ('[REDACTED]')"),
          Redactor.new(/(\s|\b|`)(=|!=|>=|>|<=|<) ?(BINARY )?-?\d+(\.\d+)?/i, " = '[REDACTED]'"),
          Redactor.new(/(\s|\b|`)(=|!=|>=|>|<=|<) ?(BINARY )?x?#{quotedValuePattern}/i, " = '[REDACTED]'"),
          Redactor.new(/VALUES \(.+\)$/i, "VALUES ('[REDACTED]')"),
          Redactor.new(/BETWEEN #{quotedValuePattern} AND #{quotedValuePattern}/i, "BETWEEN '[REDACTED]' AND '[REDACTED]'"),
          Redactor.new(/LIKE #{quotedValuePattern}/i, "LIKE '[REDACTED]'"),
          Redactor.new(/ LIMIT \d+/i, ""),
          Redactor.new(/ OFFSET \d+/i, ""),
          Redactor.new(/INSERT INTO (`?\w+`?) \([^)]+\)/i, "INSERT INTO \\1 (REDACTED_COLUMNS)"),
        ]

        @options[:should_log_sample_proc] = Proc.new { |_name| false }
        @options[:sql_redactor_complex_proc] = Proc.new { |sql| sql }
        @options[:backtrace_redactors] = []
        @options[:ambiguous_tracers] = []
        @options[:ambiguous_backtrace_lines] = 3
        @options[:analyzers] = []
        @options[:logger_root_path] = Rails.root.join('log')
        @options[:backtrace_filter_proc] = BacktraceFilter.proc
      end
    end
  end
end
