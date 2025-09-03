# frozen_string_literal: true

require_relative '../test_helper'

class TestFunctionalHelpers < DormTestCase
  include Dorm::FunctionalHelpers

  def test_pipe
    result = pipe(5,
                  ->(x) { x * 2 },
                  ->(x) { x + 1 },
                  ->(x) { x.to_s })

    assert_equal '11', result
  end

  def test_comp
    multiply_by_two = ->(x) { x * 2 }
    add_one = ->(x) { x + 1 }
    to_string = ->(x) { x.to_s }

    composed = comp(to_string, add_one, multiply_by_two)
    result = composed.call(5)

    assert_equal '11', result
  end

  def test_partial
    add = ->(a, b) { a + b }
    add_five = partial(add, 5)

    assert_equal 8, add_five.call(3)
    assert_equal 15, add_five.call(10)
  end

  def test_filter
    numbers = [1, 2, 3, 4, 5, 6]
    even_numbers = filter(numbers, ->(x) { x.even? })

    assert_equal [2, 4, 6], even_numbers
  end

  def test_map_over
    numbers = [1, 2, 3, 4]
    squared = map_over(numbers, ->(x) { x * x })

    assert_equal [1, 4, 9, 16], squared
  end

  def test_reduce_with
    numbers = [1, 2, 3, 4, 5]
    sum = reduce_with(numbers, 0, ->(acc, x) { acc + x })

    assert_equal 15, sum
  end

  def test_find_first
    numbers = [1, 3, 5, 8, 9, 12]
    first_even = find_first(numbers, ->(x) { x.even? })

    assert_equal 8, first_even
  end

  def test_find_first_no_match
    numbers = [1, 3, 5, 9]
    first_even = find_first(numbers, ->(x) { x.even? })

    assert_nil first_even
  end

  def test_take
    numbers = [1, 2, 3, 4, 5]
    first_three = take(numbers, 3)

    assert_equal [1, 2, 3], first_three
  end

  def test_drop
    numbers = [1, 2, 3, 4, 5]
    last_three = drop(numbers, 2)

    assert_equal [3, 4, 5], last_three
  end

  def test_group_by_fn
    words = %w[apple banana apricot blueberry avocado]
    grouped = group_by_fn(words, ->(word) { word[0] })

    assert_equal %w[apple apricot avocado], grouped['a']
    assert_equal %w[banana blueberry], grouped['b']
  end

  def test_sort_by_fn
    words = %w[apple hi banana a]
    sorted = sort_by_fn(words, ->(word) { word.length })

    assert_equal %w[a hi apple banana], sorted
  end

  def test_apply_if_true
    result = apply_if(10, true, ->(x) { x * 2 })
    assert_equal 20, result
  end

  def test_apply_if_false
    result = apply_if(10, false, ->(x) { x * 2 })
    assert_equal 10, result
  end

  def test_thread_first
    result = thread_first(5,
                          ->(x) { x * 2 },
                          ->(x) { x + 3 },
                          ->(x) { x / 2.0 })

    assert_equal 6.5, result
  end

  def test_juxt
    number_facts = juxt(
      ->(x) { x.even? },
      ->(x) { x > 5 },
      ->(x) { x * x }
    )

    result = number_facts.call(6)
    assert_equal [true, true, 36], result

    result = number_facts.call(3)
    assert_equal [false, false, 9], result
  end

  def test_maybe_with_value
    maybe_val = maybe(42)

    assert maybe_val.some?
    refute maybe_val.none?
    assert_equal 42, maybe_val.value_or('default')

    result = maybe_val.map { |x| x * 2 }
    assert result.some?
    assert_equal 84, result.value

    result = maybe_val.bind { |x| Some.new(x.to_s) }
    assert result.some?
    assert_equal '42', result.value
  end

  def test_maybe_with_nil
    maybe_val = maybe(nil)

    refute maybe_val.some?
    assert maybe_val.none?
    assert_equal 'default', maybe_val.value_or('default')

    result = maybe_val.map { |x| x * 2 } # Should not execute
    assert result.none?

    result = maybe_val.bind { |x| Some.new(x.to_s) } # Should not execute
    assert result.none?
  end

  def test_some_chaining
    result = Some.new(10)
                 .map { |x| x + 5 }
                 .bind { |x| Some.new(x * 2) }
                 .map { |x| x.to_s }

    assert result.some?
    assert_equal '30', result.value
  end

  def test_none_chaining_short_circuits
    result = None.new
                 .map { |x| x + 5 }
                 .bind { |x| Some.new(x * 2) }
                 .map { |x| x.to_s }

    assert result.none?
    assert_equal 'default', result.value_or('default')
  end

  def test_complex_functional_composition
    # Complex example: process a list of numbers
    numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

    result = pipe(numbers,
                  partial(method(:filter), ->(x) { x.even? }),
                  partial(method(:map_over), ->(x) { x * x }),
                  partial(method(:take), 3))

    assert_equal [4, 16, 36], result
  end

  def test_functional_pipeline_with_repository_operations
    # Skip if we don't have test data setup
    return unless defined?(Users)

    # This would be a more realistic example using the repository
    create_user_op = ->(attrs) { Users.create(attrs) }
    extract_value = ->(result) { result.success? ? result.value : nil }
    get_name = ->(user) { user&.name }

    # Create and extract name in a functional pipeline
    result = pipe({ name: 'Functional User', email: 'func@example.com', age: 28 },
                  create_user_op,
                  extract_value,
                  get_name)

    assert_equal 'Functional User', result
  end
end
