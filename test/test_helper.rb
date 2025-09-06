# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/test/"
end

require "minitest/autorun"
require "minitest/reporters"
require "fileutils"
require_relative "../lib/dorm"

# Use spec reporter for better output
Minitest::Reporters.use! [Minitest::Reporters::SpecReporter.new]

class DormTestCase < Minitest::Test
  def setup
    # Use a temporary file database instead of :memory:
    @db_file = "test_#{Process.pid}_#{Time.now.to_f.to_s.gsub(".", "")}.db"

    # Setup file-based SQLite for tests
    Dorm::Database.configure(
      adapter: :sqlite3,
      database: @db_file,
      pool_size: 20
    )

    setup_test_schema
  end

  def teardown
    # Clean up database connections and file
    Dorm::Database.disconnect! if defined?(Dorm::Database)
    FileUtils.rm_f(@db_file) if @db_file && File.exist?(@db_file)
  end

  private

  def setup_test_schema
    # Create test tables
    Dorm::Database.query(<<~SQL)
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        age INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    SQL

    Dorm::Database.query(<<~SQL)
      CREATE TABLE posts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        user_id INTEGER NOT NULL,
        published BOOLEAN DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id)
      );
    SQL

    Dorm::Database.query(<<~SQL)
      CREATE TABLE comments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        content TEXT NOT NULL,
        post_id INTEGER NOT NULL,
        user_id INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (post_id) REFERENCES posts(id),
        FOREIGN KEY (user_id) REFERENCES users(id)
      );
    SQL
  rescue StandardError => e
    puts "Schema setup failed: #{e.message}"
    puts "Database file: #{@db_file}"
    puts "Database adapter: #{begin
      Dorm::Database.adapter
    rescue StandardError
      "not configured"
    end}"
    puts "Pool configured: #{begin
      !Dorm::Database.pool.nil?
    rescue StandardError
      "no pool"
    end}"
    raise
  end
end

# Test data classes
User = Data.define(:id, :name, :email, :age, :created_at, :updated_at)
Post = Data.define(:id, :title, :body, :user_id, :published, :created_at, :updated_at)
Comment = Data.define(:id, :content, :post_id, :user_id, :created_at, :updated_at)

# Test repositories
Users = Dorm.repository_for(User,
                            validations: {
                              name: { required: true, length: 1..100 },
                              email: { required: true, format: /@/ },
                              age: { range: 0..150 }
                            })

Posts = Dorm.repository_for(Post,
                            validations: {
                              title: { required: true, length: 1..200 },
                              body: { required: true },
                              user_id: { required: true }
                            })

Comments = Dorm.repository_for(Comment,
                               validations: {
                                 content: { required: true, length: 1..1000 },
                                 post_id: { required: true },
                                 user_id: { required: true }
                               })

# Helper methods for creating test data
module TestDataHelpers
  def create_user(attrs = {})
    # Generate unique email to avoid conflicts
    email = attrs[:email] || "user_#{Time.now.to_f.to_s.gsub(".", "")}@example.com"

    default_attrs = {
      name: "John Doe",
      email: email,
      age: 30
    }

    result = Users.create(default_attrs.merge(attrs))

    # For test helpers, we want to fail fast if creation fails
    raise "Test data creation failed: #{result.error}" unless result.success?

    result
  end

  def create_post(user_id, attrs = {})
    default_attrs = {
      title: "Test Post",
      body: "This is a test post",
      user_id: user_id,
      published: true
    }

    result = Posts.create(default_attrs.merge(attrs))

    raise "Test data creation failed: #{result.error}" unless result.success?

    result
  end

  def create_comment(post_id, user_id, attrs = {})
    default_attrs = {
      content: "This is a test comment",
      post_id: post_id,
      user_id: user_id
    }

    result = Comments.create(default_attrs.merge(attrs))

    raise "Test data creation failed: #{result.error}" unless result.success?

    result
  end
end
