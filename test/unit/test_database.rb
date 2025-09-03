# frozen_string_literal: true

require_relative '../test_helper'

class TestDatabase < DormTestCase
  def test_database_configuration
    assert_equal :sqlite3, Dorm::Database.adapter
    assert_instance_of Dorm::ConnectionPool, Dorm::Database.pool
  end

  def test_pool_stats
    stats = Dorm::Database.pool_stats

    assert_equal :sqlite3, stats[:adapter]

    # Pool size may vary based on configuration - just ensure it's a positive integer
    assert_instance_of Integer, stats[:size]
    assert stats[:size] > 0, 'Pool size should be greater than 0'

    # These keys should always be present
    assert stats.has_key?(:available)
    assert stats.has_key?(:checked_out)

    # Available and checked_out should be non-negative integers
    assert_instance_of Integer, stats[:available]
    assert_instance_of Integer, stats[:checked_out]
    assert stats[:available] >= 0
    assert stats[:checked_out] >= 0
  end

  def test_simple_query
    result = Dorm::Database.query('SELECT 1 as test_value')

    assert_instance_of Array, result
    assert_equal 1, result.length
    assert_equal 1, result[0]['test_value']
  end

  def test_parameterized_query
    # Insert a test record
    Dorm::Database.query(
      'INSERT INTO users (name, email, age, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['Test User', 'test@example.com', 25, Time.now.to_s, Time.now.to_s]
    )

    # Query it back with parameters
    result = Dorm::Database.query(
      'SELECT * FROM users WHERE name = ? AND age = ?',
      ['Test User', 25]
    )

    assert_equal 1, result.length
    assert_equal 'Test User', result[0]['name']
    assert_equal 25, result[0]['age']
  end

  def test_query_with_no_results
    result = Dorm::Database.query('SELECT * FROM users WHERE name = ?', ['Nonexistent'])

    assert_instance_of Array, result
    assert_equal 0, result.length
  end

  def test_invalid_sql_raises_error
    assert_raises(Dorm::Error) do
      Dorm::Database.query('INVALID SQL QUERY')
    end
  end

  def test_transaction_commit
    initial_count = Dorm::Database.query('SELECT COUNT(*) as count FROM users')[0]['count'].to_i

    Dorm::Database.transaction do |conn|
      conn.execute(
        'INSERT INTO users (name, email, age, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
        ['Transaction User 1', 'trans1@example.com', 30, Time.now.to_s, Time.now.to_s]
      )
      conn.execute(
        'INSERT INTO users (name, email, age, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
        ['Transaction User 2', 'trans2@example.com', 35, Time.now.to_s, Time.now.to_s]
      )
    end

    final_count = Dorm::Database.query('SELECT COUNT(*) as count FROM users')[0]['count'].to_i
    assert_equal initial_count + 2, final_count
  end

  def test_transaction_rollback
    initial_count = Dorm::Database.query('SELECT COUNT(*) as count FROM users')[0]['count'].to_i

    assert_raises(Dorm::Error) do
      Dorm::Database.transaction do |conn|
        conn.execute(
          'INSERT INTO users (name, email, age, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
          ['Transaction User 1', 'trans1@example.com', 30, Time.now.to_s, Time.now.to_s]
        )
        raise Dorm::Error, 'Force rollback'
      end
    end

    final_count = Dorm::Database.query('SELECT COUNT(*) as count FROM users')[0]['count'].to_i
    assert_equal initial_count, final_count
  end

  def test_unconfigured_database_raises_error
    # Disconnect to simulate unconfigured state
    old_pool = Dorm::Database.instance_variable_get(:@pool)
    old_adapter = Dorm::Database.instance_variable_get(:@adapter)

    Dorm::Database.instance_variable_set(:@pool, nil)
    Dorm::Database.instance_variable_set(:@adapter, nil)

    error = assert_raises(Dorm::Error) do
      Dorm::Database.query('SELECT 1')
    end

    # Verify it's specifically a configuration error by checking the message
    assert_match(/Database not configured|not configured/i, error.message)

    # Restore original configuration
    Dorm::Database.instance_variable_set(:@pool, old_pool)
    Dorm::Database.instance_variable_set(:@adapter, old_adapter)
  end

  def test_multiple_queries_use_pool
    results = []
    threads = []

    5.times do |i|
      threads << Thread.new do
        result = Dorm::Database.query('SELECT ? as thread_id', [i])
        results << result[0]['thread_id'].to_i
      end
    end

    threads.each(&:join)

    assert_equal [0, 1, 2, 3, 4], results.sort
  end

  def test_database_disconnect
    # Should not raise error even if called multiple times
    # Just call the method and let any exceptions bubble up naturally
    Dorm::Database.disconnect!
    Dorm::Database.disconnect!

    # If we get here without an exception, the test passes
    assert true, 'disconnect! completed without raising an error'
  end
end
