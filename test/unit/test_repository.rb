# frozen_string_literal: true

require_relative '../test_helper'

class TestRepository < DormTestCase
  include TestDataHelpers

  def test_repository_metadata
    assert_equal User, Users.data_class
    assert_equal 'users', Users.table_name
    assert_equal %i[id name email age created_at updated_at], Users.columns
    assert_equal %i[name email age created_at updated_at], Users.db_columns

    expected_validations = {
      name: { required: true, length: 1..100 },
      email: { required: true, format: /@/ },
      age: { range: 0..150 }
    }
    assert_equal expected_validations, Users.validations
  end

  def test_create_valid_record
    result = create_user(name: 'Alice', email: 'alice@example.com', age: 25)

    assert result.success?
    user = result.value
    assert_equal 'Alice', user.name
    assert_equal 'alice@example.com', user.email
    assert_equal 25, user.age
    assert_instance_of Integer, user.id
    assert_instance_of Time, user.created_at
    assert_instance_of Time, user.updated_at
  end

  def test_create_with_validation_errors
    # Missing required field
    result = Users.create(email: 'test@example.com')
    assert result.failure?
    assert_match(/name is required/, result.error)

    # Invalid email format
    result = Users.create(name: 'Test', email: 'invalid-email')
    assert result.failure?
    assert_match(/email has invalid format/, result.error)

    # Invalid age range
    result = Users.create(name: 'Test', email: 'test@example.com', age: 200)
    assert result.failure?
    assert_match(/age must be in range/, result.error)

    # Invalid name length (empty string triggers required validation first)
    result = Users.create(name: '', email: 'test@example.com')
    assert result.failure?
    assert_match(/name is required/, result.error)

    # Invalid name length (too long - this should trigger length validation)
    long_name = 'a' * 101 # 101 characters, exceeds max of 100
    result = Users.create(name: long_name, email: 'test@example.com')
    assert result.failure?
    assert_match(/name length must be/, result.error)
  end

  def test_find_existing_record
    created_user = create_user.value

    result = Users.find(created_user.id)
    assert result.success?

    found_user = result.value
    assert_equal created_user.id, found_user.id
    assert_equal created_user.name, found_user.name
    assert_equal created_user.email, found_user.email
  end

  def test_find_nonexistent_record
    result = Users.find(99_999)
    assert result.failure?
    assert_match(/Record not found/, result.error)
  end

  def test_find_all_empty
    result = Users.find_all
    assert result.success?
    assert_equal [], result.value
  end

  def test_find_all_with_records
    user1 = create_user(name: 'Alice', email: 'alice@example.com').value
    user2 = create_user(name: 'Bob', email: 'bob@example.com').value

    result = Users.find_all
    assert result.success?

    users = result.value
    assert_equal 2, users.length
    assert_includes users.map(&:name), 'Alice'
    assert_includes users.map(&:name), 'Bob'
  end

  def test_update_existing_record
    user = create_user.value
    updated_user = user.with(name: 'Updated Name', age: 35)

    result = Users.update(updated_user)
    assert result.success?

    updated = result.value
    assert_equal user.id, updated.id
    assert_equal 'Updated Name', updated.name
    assert_equal 35, updated.age
    assert updated.updated_at > user.updated_at
  end

  def test_update_record_without_id
    user = User.new(id: nil, name: 'Test', email: 'test@example.com',
                    age: 30, created_at: Time.now, updated_at: Time.now)

    result = Users.update(user)
    assert result.failure?
    assert_match(/Cannot update record without id/, result.error)
  end

  def test_save_new_record
    user_attrs = { name: 'New User', email: 'new@example.com', age: 28 }
    user = User.new(id: nil, **user_attrs, created_at: Time.now, updated_at: Time.now)

    result = Users.save(user)
    assert result.success?

    saved_user = result.value
    assert_instance_of Integer, saved_user.id
    assert_equal 'New User', saved_user.name
  end

  def test_save_existing_record
    user = create_user.value
    modified_user = user.with(name: 'Modified Name')

    result = Users.save(modified_user)
    assert result.success?

    saved_user = result.value
    assert_equal user.id, saved_user.id
    assert_equal 'Modified Name', saved_user.name
  end

  def test_delete_existing_record
    user = create_user.value

    result = Users.delete(user)
    assert result.success?
    assert_equal user, result.value

    # Verify record is actually deleted
    find_result = Users.find(user.id)
    assert find_result.failure?
  end

  def test_delete_record_without_id
    user = User.new(id: nil, name: 'Test', email: 'test@example.com',
                    age: 30, created_at: Time.now, updated_at: Time.now)

    result = Users.delete(user)
    assert result.failure?
    assert_match(/Cannot delete record without id/, result.error)
  end

  def test_where_with_predicate
    user1 = create_user(name: 'Alice', age: 25).value
    user2 = create_user(name: 'Bob', email: 'bob@example.com', age: 35).value
    user3 = create_user(name: 'Charlie', email: 'charlie@example.com', age: 45).value

    result = Users.where(->(u) { u.age > 30 })
    assert result.success?

    filtered_users = result.value
    assert_equal 2, filtered_users.length
    assert_includes filtered_users.map(&:name), 'Bob'
    assert_includes filtered_users.map(&:name), 'Charlie'
    refute_includes filtered_users.map(&:name), 'Alice'
  end

  def test_find_by_attributes
    user = create_user(name: 'Alice', email: 'alice@example.com').value

    result = Users.find_by(name: 'Alice')
    assert result.success?
    assert_equal user.id, result.value.id

    result = Users.find_by(email: 'alice@example.com')
    assert result.success?
    assert_equal user.id, result.value.id

    result = Users.find_by(name: 'Nonexistent')
    assert result.failure?
    assert_match(/Record not found/, result.error)
  end

  def test_find_all_by_attributes
    user1 = create_user(name: 'Alice', age: 25).value
    user2 = create_user(name: 'Bob', email: 'bob@example.com', age: 25).value
    user3 = create_user(name: 'Charlie', email: 'charlie@example.com', age: 35).value

    result = Users.find_all_by(age: 25)
    assert result.success?

    users = result.value
    assert_equal 2, users.length
    assert_includes users.map(&:name), 'Alice'
    assert_includes users.map(&:name), 'Bob'
  end

  def test_count
    create_user(name: 'User1', email: 'user1@example.com')
    create_user(name: 'User2', email: 'user2@example.com')
    create_user(name: 'User3', email: 'user3@example.com')

    result = Users.count
    assert result.success?
    assert_equal 3, result.value
  end

  def test_count_empty_table
    result = Users.count
    assert result.success?
    assert_equal 0, result.value
  end

  def test_pluralization
    # Test basic pluralization
    assert_equal 'users', Dorm::Repository.pluralize('user')
    assert_equal 'posts', Dorm::Repository.pluralize('post')

    # Test 'y' ending
    assert_equal 'categories', Dorm::Repository.pluralize('category')

    # Test 's', 'x', 'z', 'ch', 'sh' endings
    assert_equal 'boxes', Dorm::Repository.pluralize('box')
    assert_equal 'classes', Dorm::Repository.pluralize('class')
    assert_equal 'buzzes', Dorm::Repository.pluralize('buzz')
    assert_equal 'watches', Dorm::Repository.pluralize('watch')
    assert_equal 'dishes', Dorm::Repository.pluralize('dish')
  end

  def test_serialize_deserialize_values
    # Create user with specific known values to test serialization/deserialization
    test_email = 'serialize_test@example.com'
    user = create_user(name: 'Serialize Test', email: test_email, age: 42).value

    # Test Time serialization/deserialization
    assert_instance_of Time, user.created_at
    assert_instance_of Time, user.updated_at

    # Test ID deserialization
    assert_instance_of Integer, user.id

    # Test normal values pass through correctly
    assert_equal 'Serialize Test', user.name
    assert_equal test_email, user.email
    assert_equal 42, user.age
  end

  def test_custom_table_name
    custom_repo = Dorm.repository_for(User, table_name: 'custom_users')
    assert_equal 'custom_users', custom_repo.table_name
  end
end
