# frozen_string_literal: true

require "bundler/gem_tasks"

require "rspec/core/rake_task"

RSpec::Core::RakeTask.new do |t|
  t.pattern = "spec/**/*_spec.rb"
  t.rspec_opts = ["--colour", "--format", "documentation"]
end

task "default" => "spec"

require "rubocop/rake_task"

RuboCop::RakeTask.new
