# frozen_string_literal: true

require 'rake/testtask'

# Default task
task default: :test

# Test task configuration
Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  t.test_files = FileList['test/**/*test*.rb']
  t.verbose = true
  t.warning = false
end

# Unit tests only
Rake::TestTask.new(:test_unit) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  t.test_files = FileList['test/unit/*test*.rb']
  t.verbose = true
  t.warning = false
end

# Integration tests only
Rake::TestTask.new(:test_integration) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  t.test_files = FileList['test/integration/*test*.rb']
  t.verbose = true
  t.warning = false
end

# Run specific test file
# Usage: rake test_file TEST=test/unit/test_result.rb
Rake::TestTask.new(:test_file) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  t.test_files = FileList[ENV['TEST']] if ENV['TEST']
  t.verbose = true
  t.warning = false
end

# Test coverage (if you add simplecov)
desc "Run tests with coverage"
task :test_coverage do
  ENV['COVERAGE'] = 'true'
  Rake::Task[:test].invoke
end

# Lint code (if you have rubocop)
task :lint do
  sh 'rubocop lib/ test/' if system('which rubocop > /dev/null 2>&1')
end

# Clean up test artifacts
task :clean do
  rm_f 'test.db'
  rm_f 'coverage/'
  rm_f '.coverage_results'
end

desc "Run all quality checks"
task quality: [:lint, :test]

# Documentation generation
task :doc do
  sh 'yard doc' if system('which yard > /dev/null 2>&1')
end

# Show available tasks
desc "Show test statistics"
task :test_stats do
  unit_tests = FileList['test/unit/*test*.rb'].count
  integration_tests = FileList['test/integration/*test*.rb'].count
  total_tests = unit_tests + integration_tests

  puts "Test Statistics:"
  puts "  Unit tests: #{unit_tests}"
  puts "  Integration tests: #{integration_tests}"
  puts "  Total test files: #{total_tests}"

  # Count individual test methods
  test_methods = 0
  FileList['test/**/*test*.rb'].each do |file|
    content = File.read(file)
    test_methods += content.scan(/def test_\w+/).count
  end

  puts "  Total test methods: #{test_methods}"
end
