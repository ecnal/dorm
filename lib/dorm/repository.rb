# frozen_string_literal: true

module Dorm
  # Metaprogramming module to generate repository methods
  module Repository
    module_function

    def for(data_class, table_name: nil, validations: {})
      table_name ||= pluralize(data_class.name.downcase)

      Module.new do
        extend self

        # Store metadata about this repository
        define_singleton_method(:data_class) { data_class }
        define_singleton_method(:table_name) { table_name }
        define_singleton_method(:validations) { validations }
        define_singleton_method(:columns) { data_class.members }
        define_singleton_method(:db_columns) { columns - [:id] }

        # Helper method to get the correct placeholder syntax for the current adapter
        define_singleton_method(:placeholder) do |index|
          case Database.adapter
          when :postgresql
            "$#{index}"
          when :sqlite3
            '?'
          else
            '?'
          end
        end

        # Helper method to generate placeholders for multiple values
        define_singleton_method(:placeholders) do |count, start_index: 1|
          case Database.adapter
          when :postgresql
            (start_index...(start_index + count)).map { |i| "$#{i}" }
          when :sqlite3
            Array.new(count, '?')
          else
            Array.new(count, '?')
          end
        end

        # Helper method to handle RETURNING clause differences
        define_singleton_method(:returning_clause) do |column = 'id'|
          case Database.adapter
          when :postgresql
            "RETURNING #{column}"
          when :sqlite3
            "RETURNING #{column}"
          else
            "RETURNING #{column}"
          end
        end

        # Helper method to check if result is empty (adapter-specific)
        define_singleton_method(:result_empty?) do |result|
          case Database.adapter
          when :postgresql
            result.ntuples == 0
          when :sqlite3
            result.empty?
          else
            result.empty?
          end
        end

        # Generate standard CRUD methods
        # Find by ID
        define_singleton_method(:find) do |id|
          Result.try do
            result = Database.query("SELECT * FROM #{table_name} WHERE id = #{placeholder(1)}", [id])
            raise 'Record not found' if result_empty?(result)

            row_to_data(result[0])
          end
        end

        # Find all records
        define_singleton_method(:find_all) do
          Result.try do
            result = Database.query("SELECT * FROM #{table_name} ORDER BY id")
            result.map { |row| row_to_data(row) }
          end
        end

        # Create new record
        define_singleton_method(:create) do |attrs|
          Result.try do
            validate_attrs(attrs)

            now = Time.now
            attrs_with_timestamps = attrs.merge(created_at: now, updated_at: now)

            # Ensure we don't have an id in the attributes for creation
            attrs_with_timestamps.delete(:id) if attrs_with_timestamps.key?(:id)

            record = data_class.new(id: nil, **attrs_with_timestamps)

            columns_list = db_columns.join(', ')
            placeholder_list = placeholders(db_columns.length).join(', ')
            values = db_columns.map { |col| serialize_value(record.send(col)) }

            result = Database.query(
              "INSERT INTO #{table_name} (#{columns_list}) VALUES (#{placeholder_list}) #{returning_clause}",
              values
            )

            # Handle different return formats
            id_value = case Database.adapter
                       when :postgresql
                         result[0]['id'].to_i
                       when :sqlite3
                         result[0]['id'].to_i
                       else
                         result[0]['id'].to_i
                       end

            record.with(id: id_value)
          end
        end

        # Update existing record
        define_singleton_method(:update) do |record|
          Result.try do
            raise 'Cannot update record without id' unless record.id

            updated_record = record.with(updated_at: Time.now)

            set_clauses = db_columns.map.with_index(1) { |col, i| "#{col} = #{placeholder(i)}" }.join(', ')
            values = db_columns.map { |col| serialize_value(updated_record.send(col)) }
            values << updated_record.id

            id_placeholder = placeholder(db_columns.length + 1)
            result = Database.query(
              "UPDATE #{table_name} SET #{set_clauses} WHERE id = #{id_placeholder} #{returning_clause}",
              values
            )

            raise 'Record not found' if result_empty?(result)

            updated_record
          end
        end

        # Save (create or update)
        define_singleton_method(:save) do |record|
          if record.id
            update(record)
          else
            attrs = record.to_h
            attrs.delete(:id) # Remove id key if present
            create(attrs)
          end
        end

        # Delete record
        define_singleton_method(:delete) do |record|
          Result.try do
            raise 'Cannot delete record without id' unless record.id

            result = Database.query(
              "DELETE FROM #{table_name} WHERE id = #{placeholder(1)} #{returning_clause}",
              [record.id]
            )
            raise 'Record not found' if result_empty?(result)

            record
          end
        end

        # Query methods
        # Where with predicate
        define_singleton_method(:where) do |predicate|
          find_all.map { |records| records.select(&predicate) }
        end

        # Find by attributes
        define_singleton_method(:find_by) do |**attrs|
          Result.try do
            conditions = attrs.keys.map.with_index(1) { |key, i| "#{key} = #{placeholder(i)}" }.join(' AND ')
            values = attrs.values.map { |val| serialize_value(val) }

            result = Database.query("SELECT * FROM #{table_name} WHERE #{conditions}", values)
            raise 'Record not found' if result_empty?(result)

            row_to_data(result[0])
          end
        end

        # Find all by attributes
        define_singleton_method(:find_all_by) do |**attrs|
          Result.try do
            conditions = attrs.keys.map.with_index(1) { |key, i| "#{key} = #{placeholder(i)}" }.join(' AND ')
            values = attrs.values.map { |val| serialize_value(val) }

            result = Database.query("SELECT * FROM #{table_name} WHERE #{conditions}", values)
            result.map { |row| row_to_data(row) }
          end
        end

        # Count records
        define_singleton_method(:count) do
          Result.try do
            result = Database.query("SELECT COUNT(*) as count FROM #{table_name}")
            case Database.adapter
            when :postgresql
              result[0]['count'].to_i
            when :sqlite3
              result[0]['count'].to_i
            else
              result[0]['count'].to_i
            end
          end
        end

        # Validation method
        define_singleton_method(:validate_attrs) do |attrs|
          validations.each do |field, rules|
            value = attrs[field]

            if rules[:required] && (value.nil? || (value.respond_to?(:empty?) && value.empty?) || (value.respond_to?(:strip) && value.strip.empty?))
              raise ValidationError, "#{field} is required"
            end

            if rules[:format] && value && !value.match?(rules[:format])
              raise ValidationError, "#{field} has invalid format"
            end

            if rules[:length] && value && !rules[:length].include?(value.length)
              raise ValidationError, "#{field} length must be #{rules[:length]}"
            end

            if rules[:range] && value && !rules[:range].include?(value)
              raise ValidationError, "#{field} must be in range #{rules[:range]}"
            end
          end
        end

        # Helper methods
        define_singleton_method(:row_to_data) do |row|
          attrs = {}
          columns.each do |col|
            attrs[col] = deserialize_value(col, row[col.to_s])
          end
          data_class.new(**attrs)
        end

        define_singleton_method(:serialize_value) do |value|
          case value
          when Time
            case Database.adapter
            when :postgresql
              value # PostgreSQL handles Time objects natively
            when :sqlite3
              value.to_s # SQLite needs string representation
            else
              value.to_s
            end
          when true, false
            case Database.adapter
            when :postgresql
              value # PostgreSQL handles booleans natively
            when :sqlite3
              value ? 1 : 0 # SQLite uses integers for booleans
            else
              value
            end
          else
            value
          end
        end

        define_singleton_method(:deserialize_value) do |column, value|
          return nil if value.nil?

          case column
          when :id, :user_id, :post_id, :comment_id
            value.to_i
          when :created_at, :updated_at
            case Database.adapter
            when :postgresql
              # PostgreSQL might return Time objects or strings
              value.is_a?(Time) ? value : Time.parse(value.to_s)
            when :sqlite3
              Time.parse(value.to_s)
            else
              Time.parse(value.to_s)
            end
          when /.*_id$/
            value.to_i
          when :published, :active, :approved
            # Handle boolean fields
            case Database.adapter
            when :postgresql
              # PostgreSQL returns actual booleans or 't'/'f' strings
              case value
              when true, 't', 'true', '1', 1
                true
              when false, 'f', 'false', '0', 0
                false
              else
                !!value
              end
            when :sqlite3
              # SQLite returns integers for booleans
              case value
              when 1, '1', 'true', true
                true
              when 0, '0', 'false', false
                false
              else
                !!value
              end
            else
              !!value
            end
          else
            value
          end
        end
      end
    end

    def pluralize(word)
      # Simple pluralization - could be enhanced with inflector gem
      case word
      when /y$/
        word.sub(/y$/, 'ies')
      when /s$/, /x$/, /z$/, /ch$/, /sh$/
        word + 'es'
      else
        word + 's'
      end
    end
  end
end
