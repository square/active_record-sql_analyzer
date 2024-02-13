module ActiveRecord
  module SqlAnalyzer
    module Monkeypatches
      module Tagger
        def initialize(*, **)
          super
          @_ar_analyzer_tag = nil
        end

        def with_tag(name)
          @_ar_analyzer_tag = name
          self
        end

        def exec_queries
          Thread.current[:_ar_analyzer_tag] ||= @_ar_analyzer_tag
          super
        ensure
          Thread.current[:_ar_analyzer_tag] = nil if @_ar_analyzer_tag
        end
      end
    end
  end
end
