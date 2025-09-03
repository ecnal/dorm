# frozen_string_literal: true

module Dorm
  # Result monad using Data - inspired by dry-monads
  module Result
    Success = Data.define(:value) do
      def success? = true
      def failure? = false

      def bind(&block)
        block.call(value)
      rescue StandardError => e
        Failure.new(error: e.message)
      end

      def map(&block)
        Success.new(value: block.call(value))
      rescue StandardError => e
        Failure.new(error: e.message)
      end

      def value_or(default = nil)
        value
      end
    end

    Failure = Data.define(:error) do
      def success? = false
      def failure? = true

      def bind(&block)
        self
      end

      def map(&block)
        self
      end

      def value_or(default = nil)
        default
      end
    end

    # Add aliases to instance methods by reopening the Data classes
    Success.class_eval do
      alias_method :fmap, :map
    end

    Failure.class_eval do
      alias_method :fmap, :map
    end

    module_function

    def success(value)
      Success.new(value: value)
    end

    def failure(error)
      Failure.new(error: error)
    end

    def try(&block)
      success(block.call)
    rescue StandardError => e
      failure(e.message)
    end

    # Combine multiple Results
    def combine(*results)
      failures = results.select(&:failure?)
      return failure(failures.map(&:error).join(', ')) unless failures.empty?

      success(results.map(&:value))
    end
  end
end
