# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

task default: :test

namespace :rbs do
  task :generate do
    sh "rbs-inline --opt-out --output lib"
  end

  task :watch do
    sh "fswatch -0 lib | xargs -n1 -0 rbs-inline --opt-out --output lib"
  rescue Interrupt
    # nop
  end
end
