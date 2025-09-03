# frozen_string_literal: true

require 'monitor'
require 'timeout'

module Dorm
  class ConnectionPool
    include MonitorMixin

    class PoolExhaustedError < StandardError; end
    class ConnectionTimeoutError < StandardError; end

    Connection = Data.define(:raw_connection, :created_at, :last_used_at) do
      def expired?(max_age)
        Time.now - created_at > max_age
      end

      def stale?(max_idle)
        Time.now - last_used_at > max_idle
      end

      def touch!
        with(last_used_at: Time.now)
      end
    end

    def initialize(
      size: 5,
      timeout: 5,
      max_age: 3600,    # 1 hour
      max_idle: 300,    # 5 minutes
      reap_frequency: 60 # 1 minute
    )
      super()

      @size = size
      @timeout = timeout
      @max_age = max_age
      @max_idle = max_idle
      @reap_frequency = reap_frequency

      @available = []
      @connections = {}
      @connection_factory = nil
      @last_reap = Time.now

      start_reaper_thread if @reap_frequency > 0
    end

    def configure_factory(&block)
      @connection_factory = block
    end

    def with_connection(&block)
      connection = checkout_connection
      begin
        result = block.call(connection.raw_connection)
        result
      rescue StandardError => e
        # If connection is bad, don't return it to pool
        remove_connection(connection)
        raise
      ensure
        # Always try to check the connection back in (if it wasn't removed)
        if connection && @connections.key?(connection.object_id)
          updated_connection = connection.touch!
          synchronize do
            # Replace the connection in the hash with the updated version
            @connections[updated_connection.object_id] = updated_connection
            @connections.delete(connection.object_id) unless connection.equal?(updated_connection)
          end
          checkin_connection(updated_connection)
        end
      end
    end

    def size
      synchronize { @connections.size }
    end

    def available_count
      synchronize { @available.size }
    end

    def checked_out_count
      synchronize { @connections.size - @available.size }
    end

    def disconnect!
      synchronize do
        @connections.each_value do |conn|
          close_connection(conn)
        end
        @connections.clear
        @available.clear
      end
    end

    # Manual cleanup of expired/stale connections
    def reap_connections!
      synchronize do
        stale_connections = @available.select do |conn|
          conn.expired?(@max_age) || conn.stale?(@max_idle)
        end

        stale_connections.each do |conn|
          @available.delete(conn)
          @connections.delete(conn.object_id)
          close_connection(conn)
        end

        @last_reap = Time.now
      end
    end

    private

    def checkout_connection
      synchronize do
        # Reap periodically
        reap_connections! if should_reap?

        # Try to get an available connection first
        conn = @available.pop

        # If no available connection, try to create a new one
        conn ||= create_connection

        # If still no connection, we need to wait for one to become available
        conn = wait_for_connection if conn.nil?

        raise PoolExhaustedError, 'Could not obtain connection' if conn.nil?

        # Mark connection as checked out
        @connections[conn.object_id] = conn
        conn
      end
    end

    def checkin_connection(connection)
      synchronize do
        # Only add back to available if it's still in our connections hash
        @available.push(connection) if @connections.key?(connection.object_id) && !@available.include?(connection)
      end
    end

    def remove_connection(connection)
      synchronize do
        @connections.delete(connection.object_id)
        @available.delete(connection)
        close_connection(connection)
      end
    end

    def create_connection
      return nil unless @connection_factory
      return nil if @connections.size >= @size

      raw_conn = @connection_factory.call
      now = Time.now
      Connection.new(
        raw_connection: raw_conn,
        created_at: now,
        last_used_at: now
      )
    rescue StandardError => e
      raise Dorm::ConfigurationError, "Failed to create database connection: #{e.message}"
    end

    def wait_for_connection
      deadline = Time.now + @timeout

      loop do
        # Check if we've exceeded the timeout first
        raise ConnectionTimeoutError, 'Timeout waiting for database connection' if Time.now >= deadline

        synchronize do
          # Check if a connection became available
          conn = @available.pop
          return conn if conn
        end

        # Small sleep to avoid busy waiting
        sleep(0.001) # 1ms
      end
    end

    def close_connection(connection)
      case connection.raw_connection
      when ->(conn) { conn.respond_to?(:close) }
        connection.raw_connection.close
      when ->(conn) { conn.respond_to?(:finish) } # PG connection
        connection.raw_connection.finish
      end
    rescue StandardError => e
      # Log error but don't raise - we're cleaning up
      puts "Warning: Error closing connection: #{e.message}"
    end

    def should_reap?
      Time.now - @last_reap > @reap_frequency
    end

    def start_reaper_thread
      @reaper_thread = Thread.new do
        loop do
          sleep(@reap_frequency)
          begin
            reap_connections!
          rescue StandardError => e
            puts "Warning: Error in connection reaper: #{e.message}"
          end
        end
      end
      @reaper_thread.name = 'Dorm Connection Pool Reaper'
    end
  end
end
