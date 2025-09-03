# Dorm Test Suite

This directory contains a comprehensive test suite for the Dorm ORM using Minitest.

## Structure

```
test/
├── test_helper.rb          # Shared test setup and utilities
├── unit/                   # Unit tests for individual components
│   ├── test_result.rb      # Result monad tests
│   ├── test_database.rb    # Database connection tests
│   ├── test_repository.rb  # Repository method tests
│   ├── test_connection_pool.rb  # Connection pool tests
│   └── test_functional_helpers.rb  # Functional programming helpers
├── integration/            # Integration tests
│   ├── test_crud_operations.rb  # End-to-end CRUD tests
│   ├── test_validations.rb     # Validation integration tests
│   └── test_transactions.rb    # Transaction tests
└── fixtures/
    └── schema.sql          # Database schema for tests
```

## Running Tests

### Prerequisites

Add the following gems to your Gemfile for testing:

```ruby
group :development, :test do
  gem 'minitest', '~> 5.0'
  gem 'minitest-reporters', '~> 1.0'
  gem 'sqlite3', '~> 1.4'  # For test database
end
```

Then run:
```bash
bundle install
```

### Running All Tests

```bash
# Using rake (recommended)
rake test

# Or directly with ruby
ruby -Ilib:test test/test_helper.rb
```

### Running Specific Test Categories

```bash
# Unit tests only
rake test_unit

# Integration tests only
rake test_integration

# Specific test file
rake test_file TEST=test/unit/test_result.rb
```

### Running Individual Tests

```bash
# Run specific test file
ruby -Ilib:test test/unit/test_result.rb

# Run specific test method
ruby -Ilib:test test/unit/test_result.rb -n test_success_creation
```

### Test Coverage (Optional)

If you add SimpleCov to your Gemfile:

```ruby
gem 'simplecov', require: false, group: :test
```

Then run:
```bash
rake test_coverage
```

## Test Database

Tests use an in-memory SQLite database that's automatically set up and torn down for each test. The schema is defined in `test_helper.rb` and includes:

- `users` table with validations
- `posts` table related to users
- `comments` table related to posts and users

## Test Data Helpers

The `TestDataHelpers` module in `test_helper.rb` provides convenience methods:

```ruby
# Create test user
user = create_user(name: "Custom Name", email: "custom@example.com")

# Create test post
post = create_post(user.id, title: "Custom Title")

# Create test comment
comment = create_comment(post.id, user.id, content: "Custom comment")
```

## Writing Tests

### Basic Test Structure

```ruby
require_relative '../test_helper'

class TestMyFeature < DormTestCase
  include TestDataHelpers  # If you need test data helpers

  def test_my_feature
    # Test setup
    user = create_user

    # Test execution
    result = Users.find(user.value.id)

    # Assertions
    assert result.success?
    assert_equal "John Doe", result.value.name
  end
end
```

### Testing Monadic Results

```ruby
def test_successful_operation
  result = Users.create(name: "Test", email: "test@example.com")

  assert result.success?
  refute result.failure?
  assert_instance_of User, result.value
end

def test_failed_operation
  result = Users.create(name: "", email: "invalid")

  assert result.failure?
  refute result.success?
  assert_match /validation error/, result.error
end
```

### Testing Chained Operations

```ruby
def test_chained_operations
  result = Users.create(name: "Test", email: "test@example.com")
    .bind { |user| Posts.create(title: "Test", body: "Body", user_id: user.id) }
    .map { |post| post.title }

  assert result.success?
  assert_equal "Test", result.value
end
```

## Test Statistics

Run `rake test_stats` to see test coverage statistics:

```
Test Statistics:
  Unit tests: 6
  Integration tests: 3
  Total test files: 9
  Total test methods: 87
```

## Debugging Tests

### Verbose Output
```bash
rake test VERBOSE=true
```

### Debugging Individual Tests
```bash
# Add debugging to specific test
def test_my_feature
  user = create_user
  p user  # Debug output
  binding.pry if defined?(Pry)  # Breakpoint
  # ... rest of test
end
```

### Test Database Inspection
```ruby
# In test methods, you can inspect the database directly:
def test_something
  result = Dorm::Database.query("SELECT * FROM users")
  puts result.inspect
  # ... continue test
end
```

## Continuous Integration

For CI environments, ensure SQLite3 is available:

```yaml
# .github/workflows/test.yml
- name: Run tests
  run: |
    bundle exec rake test
  env:
    RAILS_ENV: test
```

## Best Practices

1. **Isolation**: Each test should be independent and not rely on other tests
2. **Clean up**: Test helper automatically cleans database between tests
3. **Descriptive names**: Use descriptive test method names like `test_create_user_with_valid_data`
4. **Single responsibility**: Each test should verify one specific behavior
5. **Use helpers**: Leverage `TestDataHelpers` for common test data creation
6. **Test both success and failure**: Test both happy path and error conditions
7. **Assertions**: Use specific assertions (`assert_equal` vs `assert`)

## Troubleshooting

### Common Issues

1. **Database connection errors**: Ensure SQLite3 gem is installed
2. **Test isolation problems**: Make sure teardown is cleaning properly
3. **Timing issues**: Use `sleep` sparingly; prefer deterministic tests
4. **Memory leaks**: Watch for unclosed database connections

### Getting Help

- Check test output for specific error messages
- Use `binding.pry` for interactive debugging
- Run tests with `VERBOSE=true` for more output
- Inspect database state during tests with direct SQL queries
