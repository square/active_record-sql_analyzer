module ActiveRecord
  module SqlAnalyzer
    class CLI
      attr_reader :options, :processor

      def initialize
        @options = {
          concurrency: 6
        }
      end

      def processor
        @processor ||= ActiveRecord::SqlAnalyzer::CLIProcessor.new(options[:concurrency])
      end

      def run
        definition_logs = Dir["#{options[:log_dir]}/*_definitions.log*"].map do |path|
          [File.basename(path).gsub(/_definitions\.log.*/, ""), path]
        end

        if definition_logs.empty?
          raise ArgumentError, "Cannot find any log files in '#{options[:log_dir]}'"
        end

        # Process the definition logs
        processor.run_definition(definition_logs)

        # Process the usage logs
        usage_logs = Dir["#{options[:log_dir]}/{#{definition_logs.map(&:first).uniq.join(",")}}.log*"].map do |path|
          [File.basename(path).split(".", 2).first, path]
        end

        processor.run_usage(usage_logs)

        processor.dump(options[:dest_dir])
      end

      def parse_options(args)
        opts = OptionParser.new

        opts.on("--log-dir [DIR]", String, "Directory that logs are in") do |val|
          unless Dir.exist?(val)
            raise ArgumentError, "log directory '#{val}' does not exist"
          end

          options[:log_dir] = val
        end

        opts.on("--dest-dir [DIR]", String, "Directory to dump logs to") do |val|
          unless Dir.exist?(val)
            raise ArgumentError, "dest directory '#{val}' does not exist"
          end

          options[:dest_dir] = val
        end

        opts.on("-c", "--concurrency", Integer, "How many threads to use for processing log files") do |val|
          if val <= 0
            raise ArgumentError, "Concurrency must be >0"
          end

          options[:concurrency] = val
        end

        opts.on_tail("-h", "--help") do
          puts opts
          exit
        end

        opts.parse(args)
      end
    end
  end
end
