# frozen_string_literal: true

require_relative "dorm/version"
require_relative "dorm/result"
require_relative "dorm/database"
require_relative "dorm/repository"
require_relative "dorm/query_builder"
require_relative "dorm/connection_pool"
require_relative "dorm/functional_helpers"

module Dorm
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class ValidationError < Error; end
  class RecordNotFoundError < Error; end

  def self.configure(**options)
    Database.configure(**options)
  end

  # Convenience method for creating repositories
  def self.repository_for(data_class, **options)
    Repository.for(data_class, **options)
  end
end
