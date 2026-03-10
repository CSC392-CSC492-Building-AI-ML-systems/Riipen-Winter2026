# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rdoc/task"

RSpec::Core::RakeTask.new(:spec)

RDoc::Task.new(:rdoc) do |rdoc|
  rdoc.main = "README.md"
  rdoc.rdoc_dir = "doc"
  rdoc.rdoc_files.include("README.md", "docs/rdoc/overview.rdoc", "lib/**/*.rb")
end

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: %i[spec rubocop]
