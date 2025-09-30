# frozen_string_literal: true

require_relative "lib/dorm/version"

Gem::Specification.new do |spec|
  spec.name = "dorm"
  spec.version = Dorm::VERSION
  spec.authors = ["ecnal"]

  spec.summary       = "A functional ORM using Ruby's Data class with monadic error handling"
  spec.description   = <<~DESC
    Dorm (Data ORM) is a lightweight, functional ORM built on Ruby's Data class.
    Features immutable records, monadic error handling inspired by dry-monads,
    and a functional programming approach to database operations.
  DESC
  spec.homepage      = "https://github.com/ecnal/dorm"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ecnal/dorm"
  spec.metadata["changelog_uri"] = "https://github.com/ecnal/dorm/blob/master/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Database adapters - make these optional
  spec.add_development_dependency "pg", "~> 1.0"
  spec.add_development_dependency "sqlite3", "~> 1.4"

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.0"
  spec.add_development_dependency "yard", "~> 0.9"
end
