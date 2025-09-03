# frozen_string_literal: true

require_relative '../test_helper'

class TestTransactions < DormTestCase
  include TestDataHelpers

  def test_successful_transaction_commits
    initial_user_count = Users.count.value
    initial_post_count = Posts.count.value

    Dorm::Database.transaction do |conn|
      # Create user within transaction
      conn.execute(
        'INSERT INTO users (name, email, age, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
        ['Transaction User', 'trans@example.com', 30, Time.now.to_s, Time.now.to_s]
      )

      # Get the user ID - SQLite doesn't return it automatically like PostgreSQL
      user_result = conn.execute('SELECT last_insert_rowid() as id')
      user_id = user_result[0]['id']

      # Create post for that user - convert boolean to integer for SQLite
      conn.execute(
        'INSERT INTO posts (title, body, user_id, published, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        ['Transaction Post', 'Content', user_id, 1, Time.now.to_s, Time.now.to_s]
      )
    end

    # Verify both records were created (using separate connections after transaction)
    final_user_count = Users.count.value
    final_post_count = Posts.count.value

    assert_equal initial_user_count + 1, final_user_count
    assert_equal initial_post_count + 1, final_post_count

    # Clean up using repository methods (which get their own connections)
    user_result = Users.find_by(email: 'trans@example.com')
    assert user_result.success?, "Failed to find user: #{user_result.failure? ? user_result.error : 'Unknown error'}"
    user = user_result.value

    post_result = Posts.find_by(user_id: user.id)
    assert post_result.success?, "Failed to find post: #{post_result.failure? ? post_result.error : 'Unknown error'}"
    post = post_result.value

    delete_post_result = Posts.delete(post)
    assert delete_post_result.success?,
           "Failed to delete post: #{delete_post_result.failure? ? delete_post_result.error : 'Unknown error'}"

    delete_user_result = Users.delete(user)
    assert delete_user_result.success?,
           "Failed to delete user: #{delete_user_result.failure? ? delete_user_result.error : 'Unknown error'}"
  end

  def test_failed_transaction_rolls_back
    initial_user_count = Users.count.value
    initial_post_count = Posts.count.value

    assert_raises(Dorm::Error) do
      Dorm::Database.transaction do |conn|
        # Create user
        conn.execute(
          'INSERT INTO users (name, email, age, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
          ['Rollback User', 'rollback@example.com', 25, Time.now.to_s, Time.now.to_s]
        )

        # Force an error to trigger rollback
        raise 'Intentional error to test rollback'
      end
    end

    # Verify no records were created due to rollback
    final_user_count = Users.count.value
    final_post_count = Posts.count.value

    assert_equal initial_user_count, final_user_count
    assert_equal initial_post_count, final_post_count
  end

  def test_repository_operations_after_transaction
    # Test that repository operations work fine after transactions complete
    user_id = nil

    # Create user in transaction
    Dorm::Database.transaction do |conn|
      conn.execute(
        'INSERT INTO users (name, email, age, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
        ['Repo After Trans', 'repo@example.com', 35, Time.now.to_s, Time.now.to_s]
      )

      user_result = conn.execute('SELECT last_insert_rowid() as id')
      user_id = user_result[0]['id']
    end

    # After transaction, use repository operations
    user_result = Users.find(user_id)
    assert user_result.success?, "Failed to find user: #{user_result.failure? ? user_result.error : 'Unknown error'}"
    user = user_result.value

    post_result = Posts.create(title: 'After Transaction', body: 'Content', user_id: user.id, published: true)
    assert post_result.success?, "Failed to create post: #{post_result.failure? ? post_result.error : 'Unknown error'}"
    post = post_result.value

    refute_nil user
    refute_nil post
    assert_equal user.id, post.user_id

    # Clean up
    delete_post_result = Posts.delete(post)
    assert delete_post_result.success?,
           "Failed to delete post: #{delete_post_result.failure? ? delete_post_result.error : 'Unknown error'}"

    delete_user_result = Users.delete(user)
    assert delete_user_result.success?,
           "Failed to delete user: #{delete_user_result.failure? ? delete_user_result.error : 'Unknown error'}"
  end

  def test_transaction_isolation
    # Create initial user using repository
    user = create_user(name: 'Isolation Test', email: 'isolation@example.com').value
    original_name = user.name

    # Update within transaction using raw connection
    Dorm::Database.transaction do |conn|
      conn.execute(
        'UPDATE users SET name = ? WHERE id = ?',
        ['Updated in Transaction', user.id]
      )

      # Within transaction, we see the change via the transaction connection
      result = conn.execute('SELECT name FROM users WHERE id = ?', [user.id])
      assert_equal 'Updated in Transaction', result[0]['name']
    end

    # After transaction commits, repository should see the change
    updated_user = Users.find(user.id).value
    assert_equal 'Updated in Transaction', updated_user.name

    Users.delete(updated_user)
  end

  def test_transaction_with_database_error
    initial_count = Users.count.value

    assert_raises(Dorm::Error) do
      Dorm::Database.transaction do |conn|
        # Create a user
        conn.execute(
          'INSERT INTO users (name, email, age, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
          ['Error User', 'error@example.com', 30, Time.now.to_s, Time.now.to_s]
        )

        # Cause a database error (invalid SQL)
        conn.execute('INVALID SQL STATEMENT')
      end
    end

    # Verify rollback occurred
    final_count = Users.count.value
    assert_equal initial_count, final_count
  end

  def test_multiple_sequential_transactions
    # Test that multiple separate transactions work correctly

    # First transaction
    user1_id = nil
    Dorm::Database.transaction do |conn|
      conn.execute(
        'INSERT INTO users (name, email, age, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
        ['Multi User 1', 'multi1@example.com', 25, Time.now.to_s, Time.now.to_s]
      )
      user_result = conn.execute('SELECT last_insert_rowid() as id')
      user1_id = user_result[0]['id']
    end

    # Second transaction
    user2_id = nil
    Dorm::Database.transaction do |conn|
      conn.execute(
        'INSERT INTO users (name, email, age, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
        ['Multi User 2', 'multi2@example.com', 30, Time.now.to_s, Time.now.to_s]
      )
      user_result = conn.execute('SELECT last_insert_rowid() as id')
      user2_id = user_result[0]['id']
    end

    # Verify both users exist using repository methods
    user1 = Users.find(user1_id).value
    user2 = Users.find(user2_id).value

    refute_nil user1
    refute_nil user2
    assert_equal 'Multi User 1', user1.name
    assert_equal 'Multi User 2', user2.name

    # Clean up
    Users.delete(user1)
    Users.delete(user2)
  end

  def test_concurrent_transactions_with_larger_pool
    # This test would work better with a larger pool
    # Skip if pool size is 1
    pool_stats = Dorm::Database.pool_stats
    skip 'Concurrent transaction test requires pool size > 1' if pool_stats[:size] < 2

    results = []
    threads = []

    # Run multiple transactions concurrently
    3.times do |i|
      threads << Thread.new do
        Dorm::Database.transaction do |conn|
          conn.execute(
            'INSERT INTO users (name, email, age, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
            ["Concurrent User #{i}", "concurrent#{i}@example.com", 20 + i, Time.now.to_s, Time.now.to_s]
          )

          result = conn.execute('SELECT last_insert_rowid() as id')
          results << result[0]['id'].to_i
        end
      rescue StandardError => e
        results << "error: #{e.message}"
      end
    end

    threads.each(&:join)

    # Verify successful transactions (filter out any errors)
    successful_results = results.select { |r| r.is_a?(Integer) }
    assert successful_results.length > 0, 'At least some transactions should succeed'

    # Clean up successful insertions
    successful_results.each do |user_id|
      user = Users.find(user_id).value
      Users.delete(user)
    rescue StandardError
      # Ignore cleanup errors
    end
  end

  def test_transaction_error_handling
    # Test that transaction errors are properly wrapped
    error = assert_raises(Dorm::Error) do
      Dorm::Database.transaction do |conn|
        conn.execute('SELECT * FROM nonexistent_table')
      end
    end

    assert_match(/Transaction failed/, error.message)
  end
end
