# Connection Pool Usage Examples

require 'dorm'

# Configure with connection pooling
Dorm.configure do |config|
  config.configure(
    adapter: :postgresql,
    host: 'localhost',
    dbname: 'myapp_production',
    user: 'postgres',
    password: 'secret',

    # Pool configuration
    pool_size: 10,              # Maximum connections in pool
    pool_timeout: 5,            # Seconds to wait for connection
    max_connection_age: 3600,   # 1 hour - connections older than this get reaped
    max_idle_time: 300,         # 5 minutes - idle connections get reaped
    reap_frequency: 60          # 1 minute - how often to check for stale connections
  )
end

# For SQLite3 with pooling (useful for testing)
Dorm.configure do |config|
  config.configure(
    adapter: :sqlite3,
    database: 'myapp.db',
    pool_size: 3, # SQLite doesn't need many connections
    pool_timeout: 2
  )
end

# Usage is exactly the same - pooling is transparent
User = Data.define(:id, :name, :email, :created_at, :updated_at)
Users = Dorm.repository_for(User, validations: {
                              name: { required: true },
                              email: { required: true, format: /@/ }
                            })

# All operations automatically use the pool
user_result = Users.create(name: 'Alice', email: 'alice@example.com')

if user_result.success?
  puts 'Created user with pooled connection!'

  # Multiple concurrent operations will use different connections from pool
  threads = 10.times.map do |i|
    Thread.new do
      Users.create(name: "User #{i}", email: "user#{i}@example.com")
    end
  end

  results = threads.map(&:join).map(&:value)
  successful = results.count(&:success?)
  puts "Successfully created #{successful} users concurrently"
end

# Monitor pool health
stats = Dorm::Database.pool_stats
puts "Pool stats: #{stats}"
# => Pool stats: {:size=>3, :available=>2, :checked_out=>1, :adapter=>:postgresql}

# Graceful shutdown - disconnect all connections
at_exit do
  Dorm::Database.disconnect!
end

# Example with error handling and pool exhaustion
begin
  # This will timeout if pool is exhausted
  user = Users.find(1).value
rescue Dorm::ConnectionPool::ConnectionTimeoutError => e
  puts "Pool exhausted: #{e.message}"
rescue Dorm::ConnectionPool::PoolExhaustedError => e
  puts "No connections available: #{e.message}"
end

# Example: Custom pool monitoring
class PoolMonitor
  def self.log_stats
    stats = Dorm::Database.pool_stats
    puts "[#{Time.now}] Pool: #{stats[:checked_out]}/#{stats[:size]} connections in use"
  end
end

# Log pool stats every 30 seconds
Thread.new do
  loop do
    sleep(30)
    PoolMonitor.log_stats
  end
end
