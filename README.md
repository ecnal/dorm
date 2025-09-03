# Dorm

**D**ata **ORM** - A lightweight, functional ORM for Ruby built on the `Data` class introduced in Ruby 3.2. Features immutable records, monadic error handling, and a functional programming approach to database operations.

## Features

- 🔧 **Immutable Records**: Built on Ruby's `Data` class for immutable, value-based objects
- 🚂 **Railway-Oriented Programming**: Monadic error handling inspired by dry-monads
- 🎯 **Functional Approach**: Pure functions in modules instead of stateful classes
- 🔍 **Automatic CRUD**: Metaprogramming generates standard operations from Data class introspection
- ✅ **Built-in Validations**: Declarative validation rules with clear error messages
- 🔄 **Safe Updates**: Use `.with()` for immutable updates that return new objects
- 🗄️ **Database Agnostic**: Support for PostgreSQL and SQLite3

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'dorm'
```

And then execute:
```bash
$ bundle install
```

Or install it yourself as:
```bash
$ gem install dorm
```

## Quick Start

### 1. Configure Database Connection

```ruby
require 'dorm'

Dorm.configure do |config|
  config.configure(
    adapter: :postgresql,
    host: 'localhost',
    dbname: 'myapp_development',
    user: 'postgres'
  )
end
```

### 2. Define Your Data Structures

```ruby
User = Data.define(:id, :name, :email, :created_at, :updated_at)
Post = Data.define(:id, :title, :body, :user_id, :created_at, :updated_at)
```

### 3. Create Repositories

```ruby
Users = Dorm.repository_for(User, 
  validations: {
    name: { required: true, length: 1..100 },
    email: { required: true, format: /@/ }
  }
)

Posts = Dorm.repository_for(Post,
  validations: {
    title: { required: true, length: 1..200 },
    body: { required: true },
    user_id: { required: true }
  }
)
```

### 4. Use With Monadic Error Handling

```ruby
# Chain operations - if any fail, the rest are skipped
result = Users.create(name: "Alice", email: "alice@example.com")
  .bind { |user| Posts.create(title: "Hello", body: "World", user_id: user.id) }
  .map { |post| "Created post: #{post.title}" }

if result.success?
  puts result.value  # "Created post: Hello"
else
  puts "Error: #{result.error}"
end

# Safe value extraction with defaults
user = Users.find(1).value_or(nil)

# Check success/failure
user_result = Users.find(999)
if user_result.success?
  puts "Found: #{user_result.value.name}"
else
  puts "Not found: #{user_result.error}"
end
```

### 5. Immutable Updates

```ruby
user = Users.find(1).value
updated_user = Users.save(user.with(name: "Alice Smith"))

if updated_user.success?
  puts "Updated: #{updated_user.value.name}"
end
```

## Available Repository Methods

Every repository automatically gets these methods:

### CRUD Operations
- `find(id)` - Find record by ID
- `find_all` - Get all records
- `create(attrs)` - Create new record
- `update(record)` - Update existing record  
- `save(record)` - Create or update (based on presence of ID)
- `delete(record)` - Delete record

### Query Methods
- `where(predicate)` - Filter with a lambda/proc
- `find_by(**attrs)` - Find first record matching attributes
- `find_all_by(**attrs)` - Find all records matching attributes
- `count` - Count total records

### Examples

```ruby
# Find operations
user = Users.find(1)
all_users = Users.find_all

# Query operations
active_users = Users.where(->(u) { u.active })
user_by_email = Users.find_by(email: "alice@example.com")
posts_by_user = Posts.find_all_by(user_id: user.value.id)

# CRUD with validation
new_user = Users.create(name: "Bob", email: "bob@example.com")
updated = Users.save(new_user.value.with(name: "Robert"))
deleted = Users.delete(updated.value)
```

## Functional Composition

Use the included functional helpers for more complex operations:

```ruby
include Dorm::FunctionalHelpers

# Pipeline processing
result = pipe(
  Users.find_all.value,
  partial(method(:filter), ->(u) { u.name.length > 3 }),
  partial(method(:map_over), ->(u) { u.email })
)
```

## Validation Rules

Support for common validation patterns:

```ruby
Users = Dorm.repository_for(User,
  validations: {
    name: { 
      required: true, 
      length: 1..100 
    },
    email: { 
      required: true, 
      format: /@/ 
    },
    age: { 
      range: 0..150 
    }
  }
)
```

## Database Support

### PostgreSQL
```ruby
Dorm.configure do |config|
  config.configure(
    adapter: :postgresql,
    host: 'localhost',
    dbname: 'myapp',
    user: 'postgres',
    password: 'secret'
  )
end
```

### SQLite3
```ruby
Dorm.configure do |config|
  config.configure(
    adapter: :sqlite3,
    database: 'myapp.db'
  )
end
```

## Philosophy

This ORM embraces functional programming principles:

- **Immutability**: Records are immutable Data objects
- **Pure Functions**: Repository methods are pure functions in modules
- **Error Handling**: Railway-oriented programming with Result monads
- **Composability**: Operations can be chained and composed
- **Explicitness**: No hidden state or magic behavior

## Requirements

- Ruby >= 3.2.0 (for Data class support)
- Database adapter gem (`pg` for PostgreSQL, `sqlite3` for SQLite)

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/yourusername/dorm.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).