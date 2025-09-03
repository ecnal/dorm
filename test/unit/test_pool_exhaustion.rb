# frozen_string_literal: true

require_relative '../test_helper'

class TestPoolExhaustion < Minitest::Test
  include TestDataHelpers

  def setup
    @db_file = "test_#{Process.pid}_#{Time.now.to_f.to_s.gsub('.', '')}.db"

    Dorm::Database.configure(
      adapter: :sqlite3,
      database: @db_file,
      pool_size: 1,     # Small pool for exhaustion testing
      timeout: 0.1      # Short timeout to fail fast
    )

    setup_test_schema
  end

  def teardown
    # Clean up database connections
    Dorm::Database.disconnect! if defined?(Dorm::Database)
    File.delete(@db_file) if File.exist?(@db_file)
  end

  def test_pool_exhaustion_with_blocking_operation
    # This test validates pool exhaustion by using a more direct approach
    results = []
    connection_acquired = false

    # Create a custom operation that blocks using the pool's with_connection method
    thread = Thread.new do
      # Access the pool directly through the Database's instance variable
      pool = Dorm::Database.instance_variable_get(:@pool)
      pool.with_connection do |conn|
        connection_acquired = true
        # Execute a simple query to ensure connection is active
        case conn
        when SQLite3::Database
          conn.execute('SELECT 1')
        else
          # Handle other database types if needed
        end
        sleep 0.5 # Hold connection
        results << 'operation_completed'
      end
    rescue StandardError => e
      results << "operation_error: #{e.message}"
    end

    # Wait for connection to be acquired with timeout
    timeout = Time.now + 1
    sleep 0.01 while !connection_acquired && Time.now < timeout

    assert connection_acquired, 'Connection should have been acquired'

    # Verify pool state
    stats = Dorm::Database.pool_stats
    assert_equal 0, stats[:available], 'Pool should have no available connections'
    assert_equal 1, stats[:checked_out], 'Pool should have 1 checked out connection'

    # Now try to get another connection - should timeout
    timeout_occurred = false
    error_message = nil

    begin
      # Try to use the pool directly to avoid any Repository-level complexity
      pool = Dorm::Database.instance_variable_get(:@pool)
      Timeout.timeout(0.2) do # Give it slightly more time than pool timeout
        pool.with_connection do |conn|
          # This should never execute
          flunk 'Second connection should not have been acquired'
        end
      end
    rescue Dorm::ConnectionPool::ConnectionTimeoutError => e
      timeout_occurred = true
      error_message = e.message
    rescue Timeout::Error => e
      # This is also acceptable - means the pool is blocking
      timeout_occurred = true
      error_message = "Pool blocked as expected: #{e.message}"
    rescue StandardError => e
      error_message = "Unexpected error: #{e.class} - #{e.message}"
    end

    thread.join

    assert timeout_occurred, "Expected timeout error, got: #{error_message}"
    assert_includes results, 'operation_completed'
  end

  def test_pool_releases_connection_after_operation
    # Verify that connections are properly released after operations

    # Use the connection in a transaction
    Dorm::Database.transaction do |conn|
      conn.execute(
        'INSERT INTO users (name, email, age, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
        ['Transaction User', 'trans@example.com', 30, Time.now.to_s, Time.now.to_s]
      )
      # At this point, the connection should be checked out
      stats = Dorm::Database.pool_stats
      assert_equal 0, stats[:available], 'Connection should be checked out during transaction'
    end

    # After transaction completes, connection should be available again
    # Give it a moment for the connection to be returned
    sleep 0.01
    stats = Dorm::Database.pool_stats
    assert_equal 1, stats[:available], 'Connection should be available after transaction'
    assert_equal 0, stats[:checked_out], 'No connections should be checked out after transaction'

    # Repository operations should work
    result = Users.create(name: 'Post Transaction', email: 'post@example.com', age: 25)
    assert result.success?

    Users.delete(result.value)
  end

  def test_concurrent_connection_requests
    # Test multiple threads competing for limited connections
    pool_size = 2

    # Reconfigure with a slightly larger pool
    Dorm::Database.disconnect!
    Dorm::Database.configure(
      adapter: :sqlite3,
      database: @db_file,
      pool_size: pool_size,
      timeout: 0.2
    )

    setup_test_schema

    completed_operations = []
    failed_operations = []
    threads = []

    # Start more threads than we have connections
    thread_count = pool_size + 2

    thread_count.times do |i|
      threads << Thread.new do
        # Use a simple query operation
        result = Dorm::Database.query('SELECT COUNT(*) as count FROM users')
        completed_operations << "thread_#{i}"
      rescue Dorm::ConnectionPool::ConnectionTimeoutError, Timeout::Error => e
        failed_operations << "thread_#{i}: #{e.class}"
      rescue StandardError => e
        failed_operations << "thread_#{i}: unexpected_error #{e.class} - #{e.message}"
      end
    end

    threads.each(&:join)

    # We should have some successful operations
    assert completed_operations.size > 0, 'Some operations should have completed'

    # The total should equal our thread count
    total_operations = completed_operations.size + failed_operations.size
    assert_equal thread_count, total_operations,
                 "All threads should have completed. Completed: #{completed_operations.size}, Failed: #{failed_operations.size}"

    # puts "Completed: #{completed_operations.size}, Failed: #{failed_operations.size}"
    # puts "Failed operations: #{failed_operations}" unless failed_operations.empty?
  end

  def test_pool_stats_during_usage
    # Test that pool_stats accurately reflects pool state
    initial_stats = Dorm::Database.pool_stats

    # Should start with available connections
    assert initial_stats[:size] >= 0
    assert initial_stats[:available] >= 0
    assert_equal 0, initial_stats[:checked_out] # No connections should be checked out initially

    # Use a connection and verify stats change
    connection_used = false

    # We need to hold the connection to see it in checked_out state
    pool = Dorm::Database.instance_variable_get(:@pool)
    pool.with_connection do |conn|
      connection_used = true
      stats_during_use = Dorm::Database.pool_stats

      # During use, we should see the connection as checked out
      assert stats_during_use[:checked_out] > 0, 'Should have checked out connections during use'
      assert stats_during_use[:available] >= 0, 'Available count should be valid'
    end

    assert connection_used, 'Connection should have been used'

    # After use, connection should be available again
    final_stats = Dorm::Database.pool_stats
    assert_equal 0, final_stats[:checked_out], 'No connections should be checked out after use'
  end

  private

  def setup_test_schema
    # Create test tables with IF NOT EXISTS to avoid conflicts
    Dorm::Database.query(<<~SQL)
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        age INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    SQL

    Dorm::Database.query(<<~SQL)
      CREATE TABLE IF NOT EXISTS posts (
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
      CREATE TABLE IF NOT EXISTS comments (
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
  end
end
