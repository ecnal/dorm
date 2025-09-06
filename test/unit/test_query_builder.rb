# frozen_string_literal: true

require_relative "../test_helper"

class QueryBuilderTest < DormTestCase
  include TestDataHelpers

  def setup
    super
    @query_builder = Dorm::QueryBuilder.new("users", User)
  end

  # Basic initialization tests
  def test_initialization
    assert_equal "users", @query_builder.table_name
    assert_equal User, @query_builder.data_class
  end

  # SELECT method tests
  def test_select_with_no_arguments_uses_default
    query = @query_builder.select
    assert_equal "SELECT users.* FROM users", query.to_sql
  end

  def test_select_with_symbols
    query = @query_builder.select(:name, :email)
    assert_equal "SELECT users.name, users.email FROM users", query.to_sql
  end

  def test_select_with_strings
    query = @query_builder.select("name", "email")
    assert_equal "SELECT users.name, users.email FROM users", query.to_sql
  end

  def test_select_with_qualified_field_names
    query = @query_builder.select("users.name", "posts.title")
    assert_equal "SELECT users.name, posts.title FROM users", query.to_sql
  end

  def test_select_raw
    query = @query_builder.select_raw("COUNT(*) as count")
    assert_equal "SELECT COUNT(*) as count FROM users", query.to_sql
  end

  # WHERE method tests with hash conditions
  def test_where_with_hash
    query = @query_builder.where(name: "John", age: 30)
    expected_sql = "SELECT users.* FROM users WHERE users.name = $1 AND users.age = $2"
    assert_equal expected_sql, query.to_sql
  end

  def test_where_with_array_values
    query = @query_builder.where(id: [1, 2, 3])
    expected_sql = "SELECT users.* FROM users WHERE users.id IN ($1, $2, $3)"
    assert_equal expected_sql, query.to_sql
  end

  def test_where_with_range_values
    query = @query_builder.where(age: 18..65)
    expected_sql = "SELECT users.* FROM users WHERE users.age BETWEEN $1 AND $2"
    assert_equal expected_sql, query.to_sql
  end

  def test_where_with_nil_values
    query = @query_builder.where(email: nil)
    expected_sql = "SELECT users.* FROM users WHERE users.email IS NULL"
    assert_equal expected_sql, query.to_sql
  end

  def test_where_raw
    query = @query_builder.where_raw("name LIKE ?", "%John%")
    expected_sql = "SELECT users.* FROM users WHERE name LIKE ?"
    assert_equal expected_sql, query.to_sql
  end

  def test_chained_where_conditions
    query = @query_builder.where(name: "John").where(age: 30)
    expected_sql = "SELECT users.* FROM users WHERE users.name = $1 AND users.age = $2"
    assert_equal expected_sql, query.to_sql
  end

  # WHERE DSL tests
  def test_where_dsl_with_eq
    query = @query_builder.where { name.eq("John") }
    expected_sql = "SELECT users.* FROM users WHERE users.name = $1"
    assert_equal expected_sql, query.to_sql
  end

  def test_where_dsl_with_gt
    query = @query_builder.where { age.gt(18) }
    expected_sql = "SELECT users.* FROM users WHERE users.age > $1"
    assert_equal expected_sql, query.to_sql
  end

  def test_where_dsl_with_and
    query = @query_builder.where { name.eq("John").and(age.gt(18)) }
    expected_sql = "SELECT users.* FROM users WHERE (users.name = $1) AND (users.age > $2)"
    assert_equal expected_sql, query.to_sql
  end

  def test_where_dsl_with_or
    query = @query_builder.where { name.eq("John").or(name.eq("Jane")) }
    expected_sql = "SELECT users.* FROM users WHERE (users.name = $1) OR (users.name = $2)"
    assert_equal expected_sql, query.to_sql
  end

  def test_where_dsl_with_like
    query = @query_builder.where { name.like("%John%") }
    expected_sql = "SELECT users.* FROM users WHERE users.name LIKE $1"
    assert_equal expected_sql, query.to_sql
  end

  def test_where_dsl_with_in
    query = @query_builder.where { id.in([1, 2, 3]) }
    expected_sql = "SELECT users.* FROM users WHERE users.id IN ($1, $2, $3)"
    assert_equal expected_sql, query.to_sql
  end

  def test_where_dsl_with_null
    query = @query_builder.where { email.null }
    expected_sql = "SELECT users.* FROM users WHERE users.email IS NULL"
    assert_equal expected_sql, query.to_sql
  end

  def test_where_dsl_with_not_null
    query = @query_builder.where { email.not_null }
    expected_sql = "SELECT users.* FROM users WHERE users.email IS NOT NULL"
    assert_equal expected_sql, query.to_sql
  end

  # JOIN method tests
  def test_inner_join_with_condition
    query = @query_builder.join("posts", "users.id = posts.user_id")
    expected_sql = "SELECT users.* FROM users INNER JOIN posts ON users.id = posts.user_id"
    assert_equal expected_sql, query.to_sql
  end

  def test_left_join_with_condition
    query = @query_builder.left_join("posts", "users.id = posts.user_id")
    expected_sql = "SELECT users.* FROM users LEFT JOIN posts ON users.id = posts.user_id"
    assert_equal expected_sql, query.to_sql
  end

  def test_join_with_kwargs
    query = @query_builder.join("posts", id: :user_id)
    expected_sql = "SELECT users.* FROM users INNER JOIN posts ON users.id = posts.user_id"
    assert_equal expected_sql, query.to_sql
  end

  def test_multiple_joins
    query = @query_builder
            .join("posts", id: :user_id)
            .left_join("comments", "posts.id = comments.post_id")
    expected_sql = "SELECT users.* FROM users INNER JOIN posts ON users.id = posts.user_id LEFT JOIN comments ON posts.id = comments.post_id"
    assert_equal expected_sql, query.to_sql
  end

  def test_join_without_condition_raises_error
    assert_raises(ArgumentError) do
      @query_builder.join("posts")
    end
  end

  # GROUP BY and HAVING tests
  def test_group_by_with_symbols
    query = @query_builder.group_by(:name, :age)
    expected_sql = "SELECT users.* FROM users GROUP BY users.name, users.age"
    assert_equal expected_sql, query.to_sql
  end

  def test_group_by_with_strings
    query = @query_builder.group_by("name", "posts.category")
    expected_sql = "SELECT users.* FROM users GROUP BY users.name, posts.category"
    assert_equal expected_sql, query.to_sql
  end

  def test_having_condition
    query = @query_builder.group_by(:name).having("COUNT(*) > ?", 5)
    expected_sql = "SELECT users.* FROM users GROUP BY users.name HAVING COUNT(*) > ?"
    assert_equal expected_sql, query.to_sql
  end

  # ORDER BY tests
  def test_order_by_with_symbols
    query = @query_builder.order_by(:name, :age)
    expected_sql = "SELECT users.* FROM users ORDER BY users.name, users.age"
    assert_equal expected_sql, query.to_sql
  end

  def test_order_by_with_hash
    query = @query_builder.order_by(name: :desc, age: :asc)
    expected_sql = "SELECT users.* FROM users ORDER BY users.name DESC, users.age ASC"
    assert_equal expected_sql, query.to_sql
  end

  def test_order_helper_method
    query = @query_builder.order(:name, :desc)
    expected_sql = "SELECT users.* FROM users ORDER BY users.name DESC"
    assert_equal expected_sql, query.to_sql
  end

  # LIMIT and OFFSET tests
  def test_limit
    query = @query_builder.limit(10)
    expected_sql = "SELECT users.* FROM users LIMIT 10"
    assert_equal expected_sql, query.to_sql
  end

  def test_offset
    query = @query_builder.offset(20)
    expected_sql = "SELECT users.* FROM users OFFSET 20"
    assert_equal expected_sql, query.to_sql
  end

  def test_limit_and_offset
    query = @query_builder.limit(10).offset(20)
    expected_sql = "SELECT users.* FROM users LIMIT 10 OFFSET 20"
    assert_equal expected_sql, query.to_sql
  end

  def test_page_helper
    query = @query_builder.page(2, 15)
    expected_sql = "SELECT users.* FROM users LIMIT 15 OFFSET 15"
    assert_equal expected_sql, query.to_sql
  end

  def test_page_helper_default_per_page
    query = @query_builder.page(3)
    expected_sql = "SELECT users.* FROM users LIMIT 20 OFFSET 40"
    assert_equal expected_sql, query.to_sql
  end

  # Complex query building tests
  def test_complex_query_building
    query = @query_builder
            .select(:name, :email)
            .join("posts", id: :user_id)
            .where(age: 25..65)
            .where { name.like("%John%") }
            .group_by(:name)
            .having("COUNT(posts.id) > ?", 2)
            .order_by(name: :desc)
            .limit(10)
            .offset(5)

    sql = query.to_sql

    # Test structure instead of exact parameter positions
    assert_includes sql, "SELECT users.name, users.email FROM users"
    assert_includes sql, "INNER JOIN posts ON users.id = posts.user_id"
    assert_includes sql, "WHERE users.age BETWEEN"
    assert_includes sql, "AND users.name LIKE"
    assert_includes sql, "GROUP BY users.name"
    assert_includes sql, "HAVING COUNT(posts.id) > ?"
    assert_includes sql, "ORDER BY users.name DESC"
    assert_includes sql, "LIMIT 10 OFFSET 5"
  end

  # Execution method tests (with actual data)
  def test_execute_returns_result
    user = create_user(name: "Alice", email: "alice@example.com", age: 25)

    query_result = @query_builder.where(name: "Alice").execute

    assert query_result.success?
    assert_equal 1, query_result.value.length
    assert_equal "Alice", query_result.value.first.name
  end

  def test_to_a_returns_array
    create_user(name: "Bob", email: "bob@example.com", age: 30)

    results = @query_builder.where(name: "Bob").to_a

    assert_instance_of Array, results
    assert_equal 1, results.length
    assert_equal "Bob", results.first.name
  end

  def test_first_returns_single_record
    create_user(name: "Charlie", email: "charlie@example.com", age: 35)

    result = @query_builder.where(name: "Charlie").first

    assert result.success?
    assert_equal "Charlie", result.value.name
  end

  def test_first_returns_failure_when_no_records
    result = @query_builder.where(name: "NonExistent").first

    assert result.failure?
    assert_equal "No records found", result.error
  end

  def test_count_returns_integer
    create_user(name: "Dave", email: "dave@example.com")
    create_user(name: "Eve", email: "eve@example.com")

    result = @query_builder.count

    assert result.success?
    assert_equal 2, result.value
  end

  def test_exists_returns_boolean
    create_user(name: "Frank", email: "frank@example.com")

    exists_result = @query_builder.where(name: "Frank").exists?
    not_exists_result = @query_builder.where(name: "NonExistent").exists?

    assert exists_result.success?
    assert_equal true, exists_result.value

    assert not_exists_result.success?
    assert_equal false, not_exists_result.value
  end

  # Aggregation method tests
  def test_sum_aggregation
    create_user(name: "Grace", email: "grace@example.com", age: 25)
    create_user(name: "Henry", email: "henry@example.com", age: 35)

    result = @query_builder.sum(:age)

    assert result.success?
    assert_equal 60.0, result.value
  end

  def test_avg_aggregation
    create_user(name: "Iris", email: "iris@example.com", age: 20)
    create_user(name: "Jack", email: "jack@example.com", age: 40)

    result = @query_builder.avg(:age)

    assert result.success?
    assert_equal 30.0, result.value
  end

  def test_max_aggregation
    create_user(name: "Kate", email: "kate@example.com", age: 45)
    create_user(name: "Liam", email: "liam@example.com", age: 55)

    result = @query_builder.max(:age)

    assert result.success?
    assert_equal 55, result.value
  end

  def test_min_aggregation
    create_user(name: "Mia", email: "mia@example.com", age: 18)
    create_user(name: "Noah", email: "noah@example.com", age: 28)

    result = @query_builder.min(:age)

    assert result.success?
    assert_equal 18, result.value
  end

  # Immutability tests
  def test_query_builder_is_immutable
    original_query = @query_builder.where(name: "Test")
    modified_query = original_query.where(age: 25)

    refute_equal original_query.to_sql, modified_query.to_sql
    assert_includes original_query.to_sql, "name = $1"
    refute_includes original_query.to_sql, "age = $2"
    assert_includes modified_query.to_sql, "name = $1"
    assert_includes modified_query.to_sql, "age = $2"
  end

  def test_cloning_preserves_state
    query1 = @query_builder.select(:name).where(age: 25)
    query2 = query1.limit(10)

    assert_includes query1.to_sql, "SELECT users.name"
    assert_includes query1.to_sql, "age = $1"
    refute_includes query1.to_sql, "LIMIT"

    assert_includes query2.to_sql, "SELECT users.name"
    assert_includes query2.to_sql, "age = $1"
    assert_includes query2.to_sql, "LIMIT 10"
  end

  # Edge cases and error handling
  def test_empty_where_conditions_ignored
    query = @query_builder.where({})
    assert_equal "SELECT users.* FROM users", query.to_sql
  end

  def test_aggregations_work_with_conditions
    create_user(name: "Agg Test 1", email: "agg1@example.com", age: 20)
    create_user(name: "Agg Test 2", email: "agg2@example.com", age: 30)
    create_user(name: "Other User", email: "other@example.com", age: 50)

    # Test that aggregations work with WHERE conditions
    result = @query_builder.where { name.like("Agg Test%") }.sum(:age)
    assert result.success?
    assert_equal 50.0, result.value
  end

  # Data serialization tests
  def test_row_to_data_converts_properly
    user = create_user(name: "Serialization Test", email: "serial@example.com", age: 42)

    result = @query_builder.where(name: "Serialization Test").first

    assert result.success?
    data = result.value
    assert_instance_of User, data
    assert_equal "Serialization Test", data.name
    assert_equal "serial@example.com", data.email
    assert_equal 42, data.age
    assert_instance_of Integer, data.id
    assert_instance_of Time, data.created_at
    assert_instance_of Time, data.updated_at
  end

  def test_select_raw_with_custom_fields
    create_user(name: "Raw Test", email: "raw@example.com")

    query = @query_builder.select_raw("name, email").where(name: "Raw Test")
    result = query.first

    assert result.success?
    # Should return raw data since we're not selecting table.*
    data = result.value
    # The data should have the selected fields accessible
    if data.respond_to?(:name)
      assert_equal "Raw Test", data.name
    elsif data.respond_to?(:[])
      assert_equal "Raw Test", data["name"]
    end
  end

  # Parameter handling integration tests
  def test_complex_parameter_handling_with_execution
    create_user(name: "Param Test", email: "param@example.com", age: 25)
    create_user(name: "Param Test 2", email: "param2@example.com", age: 35)

    # Test that complex queries with multiple parameter types execute correctly
    result = @query_builder
             .where(name: "Param Test")
             .where(age: 25)
             .where { email.like("param%") }
             .execute

    assert result.success?
    assert_equal 1, result.value.length
    assert_equal "Param Test", result.value.first.name
  end

  def test_parameter_placeholders_in_dsl
    # Test that DSL generates proper parameter placeholders
    query = @query_builder.where { name.eq("John").and(age.gt(18)) }
    sql = query.to_sql

    # Should have incrementing parameter placeholders
    assert_includes sql, "$1"
    assert_includes sql, "$2"
  end
end
