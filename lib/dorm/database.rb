# frozen_string_literal: true

require_relative 'connection_pool'

module Dorm
  module Database
    extend self

    attr_reader :adapter, :pool

    def configure(adapter:, pool_size: 5, pool_timeout: 5, **options)
      @adapter = adapter.to_sym
      @connection_options = options
      @pool_size = pool_size
      @pool_timeout = pool_timeout

      # Disconnect existing pool if any
      @pool&.disconnect!

      # Create new pool
      @pool = ConnectionPool.new(
        size: pool_size,
        timeout: pool_timeout,
        max_age: options[:max_connection_age] || 3600,
        max_idle: options[:max_idle_time] || 300,
        reap_frequency: options[:reap_frequency] || 60
      )

      # Configure the connection factory
      @pool.configure_factory { establish_connection }
    end

    def query(sql, params = [])
      ensure_configured!

      @pool.with_connection do |connection|
        execute_query(connection, sql, params)
      end
    rescue StandardError => e
      raise Error, "Database query failed: #{e.message}"
    end

    def transaction(&block)
      ensure_configured!

      @pool.with_connection do |connection|
        execute_transaction(connection, &block)
      end
    rescue StandardError => e
      raise Error, "Transaction failed: #{e.message}"
    end

    # Pool statistics for monitoring
    def pool_stats
      return {} unless @pool

      {
        size: @pool.size,
        available: @pool.available_count,
        checked_out: @pool.checked_out_count,
        adapter: @adapter
      }
    end

    # Disconnect all connections (useful for testing or shutdown)
    def disconnect!
      @pool&.disconnect!
    end

    private

    def ensure_configured!
      return if @pool && @adapter

      raise ConfigurationError, 'Database not configured. Call Dorm.configure first.'
    end

    def establish_connection
      case @adapter
      when :postgresql
        require 'pg'
        conn = PG.connect(@connection_options)
        # Set some reasonable defaults for pooled connections
        conn.exec("SET application_name = 'Dorm'") if conn.respond_to?(:exec)
        conn
      when :sqlite3
        require 'sqlite3'
        db = SQLite3::Database.new(@connection_options[:database] || ':memory:')
        # Return results as hashes instead of arrays
        db.results_as_hash = true
        # Enable foreign keys and other useful pragmas
        db.execute('PRAGMA foreign_keys = ON')
        db.execute('PRAGMA journal_mode = WAL') unless @connection_options[:database] == ':memory:'
        db
      else
        raise ConfigurationError, "Unsupported database adapter: #{@adapter}"
      end
    rescue LoadError => e
      raise ConfigurationError, "Database adapter gem not found: #{e.message}"
    rescue StandardError => e
      raise ConfigurationError, "Failed to establish database connection: #{e.message}"
    end

    def execute_query(connection, sql, params)
      case @adapter
      when :postgresql
        result = connection.exec_params(sql, params)
        # Convert PG::Result to array of hashes
        result.map { |row| row }
      when :sqlite3
        if params.empty?
          connection.execute(sql)
        else
          connection.execute(sql, params)
        end
      else
        raise ConfigurationError, "Unsupported database adapter: #{@adapter}"
      end
    end

    def execute_transaction(connection, &block)
      case @adapter
      when :postgresql
        connection.transaction(&block)
      when :sqlite3
        # SQLite3's transaction method might not work as expected in all cases
        # Let's be more explicit about transaction handling
        connection.execute('BEGIN TRANSACTION')
        begin
          result = block.call(connection)
          connection.execute('COMMIT')
          result
        rescue StandardError => e
          connection.execute('ROLLBACK')
          raise
        end
      else
        raise ConfigurationError, "Unsupported database adapter: #{@adapter}"
      end
    end
  end
end
