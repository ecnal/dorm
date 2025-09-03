# Query Builder Usage Examples

require 'dorm'

# Setup
User = Data.define(:id, :name, :email, :age, :created_at, :updated_at)
Post = Data.define(:id, :title, :body, :user_id, :status, :created_at, :updated_at)

Users = Dorm.repository_for(User)
Posts = Dorm.repository_for(Post)

# === BASIC QUERIES ===

# Simple where conditions
active_users = Users.query
  .where(status: 'active')
  .to_a

# Multiple conditions (hash style)  
young_active_users = Users.query
  .where(status: 'active', age: 18..30)
  .to_a

# Raw SQL conditions
power_users = Users.query
  .where_raw("post_count > ? AND last_login > ?", 10, 1.week.ago)
  .to_a

# === DSL WHERE CONDITIONS ===

# Elegant DSL syntax
sophisticated_query = Users.query
  .where { name.like("%admin%").and(age.gt(21)) }
  .to_a

# Complex conditions with OR
complex_users = Users.query
  .where { name.eq("Alice").or(email.like("%@admin.com")) }
  .to_a

# IN conditions
specific_users = Users.query
  .where { id.in([1, 2, 3, 4, 5]) }
  .to_a

# NULL checks
incomplete_profiles = Users.query
  .where { email.null.or(name.null) }
  .to_a

# === SELECT AND PROJECTION ===

# Select specific fields
user_emails = Users.query
  .select(:name, :email)
  .where(status: 'active')
  .to_a

# Raw select with calculations
user_stats = Users.query
  .select_raw("name, email, EXTRACT(year FROM created_at) as signup_year")
  .to_a

# === JOINS ===

# Inner join with automatic field mapping
posts_with_authors = Posts.query
  .join(:users, user_id: :id)
  .select("posts.*", "users.name as author_name")
  .to_a

# Left join with custom condition
all_posts_with_optional_authors = Posts.query
  .left_join(:users, "users.id = posts.user_id")
  .to_a

# Multiple joins
posts_with_comments = Posts.query
  .join(:users, user_id: :id)
  .left_join(:comments, "comments.post_id = posts.id")
  .group_by("posts.id", "users.name")
  .select_raw("posts.*, users.name as author, COUNT(comments.id) as comment_count")
  .to_a

# === ORDERING AND LIMITING ===

# Order by single field
recent_posts = Posts.query
  .order_by(:created_at => :desc)
  .limit(10)
  .to_a

# Multiple order fields
sorted_users = Users.query
  .order_by(:status, :name => :asc)
  .to_a

# Pagination
page_2_users = Users.query
  .page(2, per_page: 20)  # page 2, 20 per page
  .to_a

# === AGGREGATIONS ===

# Count records
user_count = Users.query
  .where(status: 'active')
  .count
  .value_or(0)

# Sum, average, min, max  
stats = {
  total_age: Users.query.sum(:age).value_or(0),
  avg_age: Users.query.avg(:age).value_or(0),
  oldest: Users.query.max(:age).value_or(0),
  youngest: Users.query.min(:age).value_or(0)
}

# Group by with aggregation
posts_by_status = Posts.query
  .group_by(:status)
  .select_raw("status, COUNT(*) as post_count")
  .to_a

# Having clause
popular_authors = Posts.query
  .join(:users, user_id: :id)
  .group_by("users.id", "users.name")
  .having("COUNT(posts.id) > ?", 5)
  .select_raw("users.name, COUNT(posts.id) as post_count")
  .to_a

# === EXECUTION METHODS ===

# Convert to array (execute immediately)
users_array = Users.query.where(status: 'active').to_a

# Get first result
first_admin = Users.query
  .where { name.like("%admin%") }
  .first

if first_admin.success?
  puts "Found admin: #{first_admin.value.name}"
end

# Check if any records exist
has_active_users = Users.query
  .where(status: 'active')
  .exists?
  .value_or(false)

# Get raw SQL for debugging
sql = Users.query
  .where(status: 'active')
  .join(:posts, user_id: :id)
  .limit(10)
  .to_sql

puts "Generated SQL: #{sql}"

# === FUNCTIONAL COMPOSITION ===

# Chain query building functionally
build_user_query = ->(status, min_age) {
  Users.query
    .where(status: status)
    .where { age.gte(min_age) }
    .order_by(:name)
}

# Use the builder
active_adults = build_user_query.call('active', 18).to_a
inactive_seniors = build_user_query.call('inactive', 65).limit(5).to_a

# === RESULT HANDLING ===

# All query results are wrapped in Result monads
Users.query
  .where(id: 999)
  .first
  .bind { |user| Posts.query.where(user_id: user.id).to_a }
  .map { |posts| posts.map(&:title) }
  .value_or([])

# === COMPLEX EXAMPLE ===

# Find popular posts by active users with recent activity
popular_recent_posts = Posts.query
  .join(:users, user_id: :id)
  .where { status.eq('published') }
  .where { created_at.gte(1.month.ago) }
  .where("users.status = ?", 'active')
  .left_join(:comments, "comments.post_id = posts.id")
  .group_by("posts.id", "posts.title", "users.name")
  .having("COUNT(comments.id) > ?", 5)
  .order_by(created_at: :desc)
  .select_raw("posts.*, users.name as author, COUNT(comments.id) as comment_count")
  .limit(20)
  .to_a

puts "Found #{popular_recent_posts.length} popular recent posts"