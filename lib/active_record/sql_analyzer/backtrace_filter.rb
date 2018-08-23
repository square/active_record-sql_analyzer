require "pathname"

# This is a bit complex but can't be avoided since otherwise we have to log 5000000 backtrace lines
module ActiveRecord
  module SqlAnalyzer
    class BacktraceFilter
      def self.library_paths
        @library_paths ||= begin
          paths = Gem.path + Gem.path.map { |f| File.realpath(f) }
          paths << "(eval):"
          paths << RbConfig::CONFIG.fetch('libdir')
          paths
        end
      end

      def self.rails_root_regex
        @rails_root_regex ||= %r{^#{Regexp.escape(Rails.root.to_s)}}
      end

      def self.proc
        @proc ||= Proc.new do |lines|
          filtered = []
          lines.each do |line|
            unless library_paths.any? { |path| line.include?(path) }
              if line =~ rails_root_regex
                filtered << Pathname.new(line).relative_path_from(Rails.root).to_s
              else
                filtered << line
              end
            end
          end

          filtered
        end
      end
    end
  end
end
