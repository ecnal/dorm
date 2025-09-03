# frozen_string_literal: true

require_relative '../test_helper'

class TestResult < DormTestCase
  def test_success_creation
    result = Dorm::Result.success('hello')

    assert result.success?
    refute result.failure?
    assert_equal 'hello', result.value
    assert_equal 'hello', result.value_or('default')
  end

  def test_failure_creation
    result = Dorm::Result.failure('error message')

    refute result.success?
    assert result.failure?
    assert_equal 'error message', result.error
    assert_equal 'default', result.value_or('default')
  end

  def test_success_bind_with_success
    result = Dorm::Result.success(5)
                         .bind { |x| Dorm::Result.success(x * 2) }

    assert result.success?
    assert_equal 10, result.value
  end

  def test_success_bind_with_failure
    result = Dorm::Result.success(5)
                         .bind { |x| Dorm::Result.failure('error') }

    assert result.failure?
    assert_equal 'error', result.error
  end

  def test_failure_bind_short_circuits
    result = Dorm::Result.failure('original error')
                         .bind { |x| Dorm::Result.success('should not execute') }

    assert result.failure?
    assert_equal 'original error', result.error
  end

  def test_success_map
    result = Dorm::Result.success(5)
                         .map { |x| x * 2 }

    assert result.success?
    assert_equal 10, result.value
  end

  def test_success_map_with_exception
    result = Dorm::Result.success(5)
                         .map { |x| raise 'boom' }

    assert result.failure?
    assert_equal 'boom', result.error
  end

  def test_failure_map_short_circuits
    result = Dorm::Result.failure('error')
                         .map { |x| x * 2 }

    assert result.failure?
    assert_equal 'error', result.error
  end

  def test_try_with_success
    result = Dorm::Result.try { 5 + 5 }

    assert result.success?
    assert_equal 10, result.value
  end

  def test_try_with_exception
    result = Dorm::Result.try { raise 'boom' }

    assert result.failure?
    assert_equal 'boom', result.error
  end

  def test_chaining_operations
    result = Dorm::Result.success(5)
                         .bind { |x| Dorm::Result.success(x * 2) }
                         .map { |x| x + 1 }
                         .bind { |x| Dorm::Result.success(x.to_s) }

    assert result.success?
    assert_equal '11', result.value
  end

  def test_chaining_with_early_failure
    result = Dorm::Result.success(5)
                         .bind { |x| Dorm::Result.success(x * 2) }
                         .bind { |x| Dorm::Result.failure('failed here') }
                         .map { |x| x + 1 } # Should not execute

    assert result.failure?
    assert_equal 'failed here', result.error
  end

  def test_combine_all_success
    results = [
      Dorm::Result.success(1),
      Dorm::Result.success(2),
      Dorm::Result.success(3)
    ]

    combined = Dorm::Result.combine(*results)

    assert combined.success?
    assert_equal [1, 2, 3], combined.value
  end

  def test_combine_with_failures
    results = [
      Dorm::Result.success(1),
      Dorm::Result.failure('error1'),
      Dorm::Result.failure('error2')
    ]

    combined = Dorm::Result.combine(*results)

    assert combined.failure?
    assert_equal 'error1, error2', combined.error
  end

  def test_monadic_aliases
    result = Dorm::Result.success(5)

    # Test fmap alias for map
    mapped_result = result.fmap { |x| x + 1 }
    assert mapped_result.success?
    assert_equal 6, mapped_result.value
  end
end
