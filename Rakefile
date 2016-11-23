require 'bundler/gem_tasks'

begin
  require "rubocop/rake_task"
  require "rspec/core/rake_task"

  RuboCop::RakeTask.new
  RSpec::Core::RakeTask.new(:spec)

  task default: [:rubocop, :spec]
rescue LoadError
  warn "rubocop, rspec only available in development"
end
