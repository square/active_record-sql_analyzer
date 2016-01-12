module ActiveRecord
  module SqlAnalyzer
    class CLIProcessor
      attr_reader :concurrency, :definitions

      def initialize(concurrency)
        @concurrency = concurrency
        @definitions = {}
      end

      def self.process_queue(queue)
        local_data = {}

        while !queue.empty? do
          prefix, path = queue.pop
          local_data[prefix] ||= {}

          File.open(path, "r") do |io|
            while !io.eof? do
              yield local_data[prefix], io.readline.strip
            end
          end
        end

        local_data

      rescue => ex
        puts "#{ex.class}: #{ex.message}"
        puts ex.backtrace
        raise
      end

      def run_definition(logs)
        queue = Queue.new
        logs.each { |l| queue << l }

        # Spin up threads to start processing the queue
        threads = concurrency.times.map do
          Thread.new(queue) do |t_queue|
            # Create a local copy of each definitions then merge them in
            CLIProcessor.process_queue(t_queue) do |local_definitions, line|
              line.strip!

              unless line == ""
                sha, event = line.split("|", 2)
                local_definitions[sha] = JSON.parse(event)
              end
            end
          end
        end

        # Merge everything
        threads.each do |thread|
          thread.value.each do |prefix, data|
            definitions[prefix] ||= {}
            definitions[prefix].merge!(data)
          end
        end
      end

      def run_usage(logs)
        queue = Queue.new
        logs.each { |l| queue << l }

        # Spin up threads to start processing the queue
        threads = concurrency.times.map do
          Thread.new(queue) do |t_queue|
            # Create a local copy of the usage for each SHA then merge it in at the end
            CLIProcessor.process_queue(t_queue) do |local_usage, line|
              line.strip!

              unless line == ""
                last_called, sha = line.split("|", 2)
                last_called = Time.at(last_called.to_i).utc

                local_usage[sha] ||= {"count" => 0}
                local_usage[sha]["count"] += 1

                if !local_usage[sha]["last_called"] || local_usage[sha]["last_called"] < last_called
                  local_usage[sha]["last_called"] = last_called
                end
              end
            end
          end
        end

        # Merge everything
        threads.each do |thread|
          thread.value.each do |prefix, data|
            definitions[prefix] ||= {}

            data.each do |sha, usage|
              definition = definitions[prefix][sha]
              unless definition
                puts "Undefined event '#{sha}'"
                next
              end

              definition["count"] ||= 0
              definition["count"] += usage["count"]

              if !definition["last_called"] || definition["last_called"] < usage["last_called"]
                definition["last_called"] = usage["last_called"]
              end
            end
          end
        end
      end

      def dump(dest_dir)
        definitions.each do |prefix, data|
          path = "#{dest_dir}/#{prefix}_#{Time.now.strftime("%Y-%m-%d")}.log"
          puts "Writing logs to '#{path}' (#{data.length} queries)"

          File.open(path, "w+") do |io|
            io.write(data.to_json)
          end
        end
      end
    end
  end
end
