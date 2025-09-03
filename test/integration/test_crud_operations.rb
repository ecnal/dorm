# frozen_string_literal: true

require_relative '../test_helper'

class TestCrudOperations < DormTestCase
  include TestDataHelpers

  def test_complete_user_lifecycle
    # Create
    user_result = Users.create(
      name: 'Integration Test User',
      email: 'integration@example.com',
      age: 28
    )

    assert user_result.success?
    user = user_result.value
    assert_instance_of Integer, user.id
    assert_equal 'Integration Test User', user.name
    assert_equal 'integration@example.com', user.email
    assert_equal 28, user.age
    assert_instance_of Time, user.created_at
    assert_instance_of Time, user.updated_at

    # Read
    found_result = Users.find(user.id)
    assert found_result.success?
    found_user = found_result.value
    assert_equal user.id, found_user.id
    assert_equal user.name, found_user.name
    assert_equal user.email, found_user.email

    # Update
    updated_user = found_user.with(name: 'Updated Name', age: 29)
    update_result = Users.update(updated_user)
    assert update_result.success?

    final_user = update_result.value
    assert_equal user.id, final_user.id
    assert_equal 'Updated Name', final_user.name
    assert_equal 29, final_user.age
    assert final_user.updated_at > user.updated_at

    # Delete
    delete_result = Users.delete(final_user)
    assert delete_result.success?

    # Verify deletion
    find_deleted_result = Users.find(user.id)
    assert find_deleted_result.failure?
  end

  def test_related_models_crud
    # Create a user first
    user_result = create_user(name: 'Author', email: 'author@example.com')
    assert user_result.success?, "Failed to create user: #{user_result.failure? ? user_result.error : 'Unknown error'}"
    user = user_result.value

    # Create posts for the user
    post1_result = create_post(user.id, title: 'First Post', body: 'Content 1')
    assert post1_result.success?,
           "Failed to create first post: #{post1_result.failure? ? post1_result.error : 'Unknown error'}"
    post1 = post1_result.value

    post2_result = create_post(user.id, title: 'Second Post', body: 'Content 2')
    assert post2_result.success?,
           "Failed to create second post: #{post2_result.failure? ? post2_result.error : 'Unknown error'}"
    post2 = post2_result.value

    # Verify posts were created with correct user_id
    assert_equal user.id, post1.user_id
    assert_equal user.id, post2.user_id

    # Find posts by user_id
    user_posts_result = Posts.find_all_by(user_id: user.id)
    assert user_posts_result.success?,
           "Failed to find posts by user_id: #{user_posts_result.failure? ? user_posts_result.error : 'Unknown error'}"
    user_posts = user_posts_result.value
    assert_equal 2, user_posts.length

    post_titles = user_posts.map(&:title).sort
    assert_equal ['First Post', 'Second Post'], post_titles

    # Create comments on posts
    comment1_result = create_comment(post1.id, user.id, content: 'Great post!')
    assert comment1_result.success?,
           "Failed to create first comment: #{comment1_result.failure? ? comment1_result.error : 'Unknown error'}"
    comment1 = comment1_result.value

    comment2_result = create_comment(post2.id, user.id, content: 'Interesting read.')
    assert comment2_result.success?,
           "Failed to create second comment: #{comment2_result.failure? ? comment2_result.error : 'Unknown error'}"
    comment2 = comment2_result.value

    # Verify comments
    post1_comments_result = Comments.find_all_by(post_id: post1.id)
    assert post1_comments_result.success?,
           "Failed to find comments for post1: #{post1_comments_result.failure? ? post1_comments_result.error : 'Unknown error'}"
    post1_comments = post1_comments_result.value
    assert_equal 1, post1_comments.length
    assert_equal 'Great post!', post1_comments.first.content

    # Update post
    updated_post_result = Posts.update(post1.with(title: 'Updated First Post'))
    assert updated_post_result.success?,
           "Failed to update post: #{updated_post_result.failure? ? updated_post_result.error : 'Unknown error'}"
    updated_post = updated_post_result.value
    assert_equal 'Updated First Post', updated_post.title

    # Clean up - delete in proper order due to foreign keys
    comment1_delete = Comments.delete(comment1)
    assert comment1_delete.success?,
           "Failed to delete comment1: #{comment1_delete.failure? ? comment1_delete.error : 'Unknown error'}"

    comment2_delete = Comments.delete(comment2)
    assert comment2_delete.success?,
           "Failed to delete comment2: #{comment2_delete.failure? ? comment2_delete.error : 'Unknown error'}"

    post1_delete = Posts.delete(post1)
    assert post1_delete.success?,
           "Failed to delete post1: #{post1_delete.failure? ? post1_delete.error : 'Unknown error'}"

    post2_delete = Posts.delete(post2)
    assert post2_delete.success?,
           "Failed to delete post2: #{post2_delete.failure? ? post2_delete.error : 'Unknown error'}"

    user_delete = Users.delete(user)
    assert user_delete.success?, "Failed to delete user: #{user_delete.failure? ? user_delete.error : 'Unknown error'}"
  end

  def test_bulk_operations
    # Create multiple users
    users = []
    5.times do |i|
      result = Users.create(
        name: "User #{i}",
        email: "user#{i}@example.com",
        age: 20 + i
      )
      assert result.success?
      users << result.value
    end

    # Verify all users were created
    all_users = Users.find_all.value
    assert_equal 5, all_users.length

    # Test filtering
    young_users = Users.where(->(u) { u.age < 23 }).value
    assert_equal 3, young_users.length

    # Test finding by attributes
    user_22 = Users.find_by(age: 22).value
    assert_equal 'User 2', user_22.name

    # Test count
    total_count = Users.count.value
    assert_equal 5, total_count

    # Clean up
    users.each { |user| Users.delete(user) }
  end

  def test_error_handling_in_operations
    # Test duplicate email constraint (if enforced by DB)
    user1 = create_user(email: 'unique@example.com').value

    # Attempt to create user with same email might fail depending on DB constraints
    # For now, this will succeed in our simple test setup
    user2_result = Users.create(name: 'Different User', email: 'unique@example.com', age: 25)
    # In a real scenario with UNIQUE constraints, this would fail

    # Test invalid data
    invalid_result = Users.create(name: '', email: 'invalid-email', age: 200)
    assert invalid_result.failure?
    assert_match(/name/, invalid_result.error)

    # Test updating non-existent record
    fake_user = User.new(id: 99_999, name: 'Fake', email: 'fake@example.com',
                         age: 30, created_at: Time.now, updated_at: Time.now)
    update_result = Users.update(fake_user)
    assert update_result.failure?
    assert_match(/Record not found/, update_result.error)

    # Clean up
    Users.delete(user1) if user1
  end

  def test_chained_monadic_operations
    # Test successful chain
    result = Users.create(name: 'Chain User', email: 'chain@example.com', age: 30)
                  .bind { |user| Posts.create(title: 'Chain Post', body: 'Content', user_id: user.id, published: true) }
                  .bind { |post| Comments.create(content: 'Chain Comment', post_id: post.id, user_id: post.user_id) }
                  .map { |comment| "Created comment: #{comment.content}" }

    assert result.success?,
           "Expected successful chain but got failure: #{result.failure? ? result.error : 'Unknown error'}"
    assert_equal 'Created comment: Chain Comment', result.value

    # Clean up the successful chain
    if result.success?
      # We need to clean up in reverse order
      # Find the created records to clean them up
      chain_user = Users.find_by(email: 'chain@example.com')
      if chain_user.success?
        user = chain_user.value
        user_posts = Posts.find_all_by(user_id: user.id)
        if user_posts.success?
          user_posts.value.each do |post|
            post_comments = Comments.find_all_by(post_id: post.id)
            post_comments.value.each { |comment| Comments.delete(comment) } if post_comments.success?
            Posts.delete(post)
          end
        end
        Users.delete(user)
      end
    end

    # Test chain with early failure - try to create a post with invalid user_id
    failure_result = Users.create(name: 'Temp User', email: 'temp@example.com', age: 25)
                          .bind do |user|
      # Delete the user first to make the next operation fail
      Users.delete(user)
      # Now try to create a post with the deleted user's ID
      Posts.create(title: 'Should fail', body: 'Content', user_id: user.id, published: true)
    end
      .map { |post| 'Should not reach here' }

    assert failure_result.failure?,
           "Expected chain to fail but it succeeded: #{failure_result.success? ? failure_result.value : 'N/A'}"

    # Alternative test for early failure using clearly invalid data
    # Test with a non-existent user_id that should definitely fail
    alt_failure_result = Dorm::Result::Success.new(User.new(id: 99_999, name: 'Fake', email: 'fake@example.com', age: 30,
                                                            created_at: Time.now, updated_at: Time.now))
                                              .bind do |user|
      Posts.create(title: 'Should fail', body: 'Content', user_id: user.id, published: true)
    end
                                        .map do |post|
      'Should not reach here'
    end

    assert alt_failure_result.failure?, 'Expected alternative chain to fail but it succeeded'
  end

  def test_save_method_create_vs_update
    # Test save with new record (should create)
    new_user = User.new(
      id: nil,
      name: 'New User',
      email: 'new@example.com',
      age: 25,
      created_at: Time.now,
      updated_at: Time.now
    )

    save_result = Users.save(new_user)
    assert save_result.success?
    saved_user = save_result.value
    assert_instance_of Integer, saved_user.id

    # Test save with existing record (should update)
    modified_user = saved_user.with(name: 'Modified Name')
    update_result = Users.save(modified_user)
    assert update_result.success?

    updated_user = update_result.value
    assert_equal saved_user.id, updated_user.id
    assert_equal 'Modified Name', updated_user.name
    assert updated_user.updated_at > saved_user.updated_at

    # Clean up
    Users.delete(updated_user)
  end

  def test_immutability_preserved
    # Create user
    user_result = create_user
    assert user_result.success?, "Failed to create user: #{user_result.failure? ? user_result.error : 'Unknown error'}"
    user = user_result.value

    original_name = user.name
    original_updated_at = user.updated_at

    # Test immutability of the .with method
    modified_user = user.with(name: 'Changed Name')

    # Verify original user object is unchanged
    assert_equal original_name, user.name, 'Original user name should be unchanged'
    assert_equal 'Changed Name', modified_user.name, 'Modified user should have new name'
    assert_equal original_updated_at, user.updated_at, 'Original user updated_at should be unchanged'

    # Test that we can update in database
    # puts "Attempting to update user with ID: #{modified_user.id}"
    update_result = Users.update(modified_user)

    if update_result.failure?
      puts "Update failed with error: #{update_result.error}"
      puts "Modified user details: #{modified_user.inspect}"
    end

    assert update_result.success?,
           "Failed to update user: #{update_result.failure? ? update_result.error : 'Unknown error'}"
    updated_user = update_result.value

    # Verify the update worked
    assert_equal 'Changed Name', updated_user.name, 'Updated user should have new name'
    assert updated_user.updated_at > original_updated_at, 'Updated user should have newer timestamp'

    # Verify original user object is still unchanged after database update
    assert_equal original_name, user.name, 'Original user name should still be unchanged after DB update'
    assert_equal original_updated_at, user.updated_at,
                 'Original user updated_at should still be unchanged after DB update'

    # Clean up
    delete_result = Users.delete(updated_user)
    assert delete_result.success?,
           "Failed to delete user: #{delete_result.failure? ? delete_result.error : 'Unknown error'}"
  end

  def test_timestamp_handling
    user = create_user.value
    original_created_at = user.created_at
    original_updated_at = user.updated_at

    sleep 0.001 # Ensure time difference

    # Update user
    updated_user = Users.update(user.with(name: 'Updated')).value

    # created_at should remain the same, updated_at should change
    assert_equal original_created_at.to_i, updated_user.created_at.to_i
    assert updated_user.updated_at > original_updated_at

    Users.delete(updated_user)
  end
end
