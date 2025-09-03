# frozen_string_literal: true

module Dorm
  # Functional composition helpers - inspired by Clojure
  module FunctionalHelpers
    module_function

    # Pipe value through a series of functions
    # pipe(value, f1, f2, f3) equivalent to f3(f2(f1(value)))
    def pipe(value, *functions)
      functions.reduce(value) { |v, f| f.call(v) }
    end

    # Compose functions into a single function
    # comp(f1, f2, f3) returns ->(x) { f1(f2(f3(x))) }
    def comp(*functions)
      ->(x) { functions.reverse.reduce(x) { |v, f| f.call(v) } }
    end

    # Partial application - fix some arguments
    # partial(method(:add), 5) returns ->(x) { add(5, x) }
    def partial(func, *args)
      # ->(x) { func.call(*args, x) }
      if [method(:filter), method(:map_over), method(:take)].include?(func)
        ->(x) { func.call(x, *args) }
      else
        ->(x) { func.call(*args, x) }
      end
    end

    # Filter collection with predicate
    def filter(collection, predicate)
      collection.select(&predicate)
    end

    # Map over collection
    def map_over(collection, transform)
      collection.map(&transform)
    end

    # Reduce collection
    def reduce_with(collection, initial, reducer)
      collection.reduce(initial, &reducer)
    end

    # Find first element matching predicate
    def find_first(collection, predicate)
      collection.find(&predicate)
    end

    # Take first n elements
    def take(collection, n)
      collection.take(n)
    end

    # Drop first n elements
    def drop(collection, n)
      collection.drop(n)
    end

    # Group by a function result
    def group_by_fn(collection, grouper)
      collection.group_by(&grouper)
    end

    # Sort by a function result
    def sort_by_fn(collection, sorter)
      collection.sort_by(&sorter)
    end

    # Apply function if condition is true, otherwise return original value
    def apply_if(value, condition, func)
      condition ? func.call(value) : value
    end

    # Thread-first macro simulation (Clojure's ->)
    # thread_first(x, f1, f2, f3) equivalent to f3(f2(f1(x)))
    def thread_first(value, *functions)
      pipe(value, *functions)
    end

    # Thread-last macro simulation (Clojure's ->>)
    # thread_last(x, f1, f2, f3) equivalent to f3(f2(f1(x)))
    # Useful when you want the value to be the last argument
    def thread_last(value, *functions)
      functions.reduce(value) do |v, f|
        if f.respond_to?(:curry)
          f.curry.call(v)
        else
          f.call(v)
        end
      end
    end

    # Juxt - apply multiple functions to same value, return array of results
    # juxt(f1, f2, f3) returns ->(x) { [f1(x), f2(x), f3(x)] }
    def juxt(*functions)
      ->(x) { functions.map { |f| f.call(x) } }
    end

    # Maybe monad helpers for dealing with nils
    def maybe(value)
      value.nil? ? None.new : Some.new(value)
    end

    Some = Data.define(:value) do
      def bind(&block)
        result = block.call(value)
        result.is_a?(Some) || result.is_a?(None) ? result : Some.new(result)
      end

      def map(&block)
        Some.new(block.call(value))
      end

      def value_or(_default)
        value
      end

      def some? = true
      def none? = false
    end

    None = Data.define do
      def bind(&block)
        self
      end

      def map(&block)
        self
      end

      def value_or(default)
        default
      end

      def some? = false
      def none? = true
    end
  end
end
