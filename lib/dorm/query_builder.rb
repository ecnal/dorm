# frozen_string_literal: true

module Dorm
  class QueryBuilder
    attr_reader :table_name, :data_class

    def initialize(table_name, data_class)
      @table_name = table_name
      @data_class = data_class
      @select_fields = ["#{table_name}.*"]
      @joins = []
      @where_conditions = []
      @group_by_fields = []
      @having_conditions = []
      @order_by_fields = []
      @limit_value = nil
      @offset_value = nil
      @params = []
      @param_counter = 0
    end

    # SELECT methods
    def select(*fields)
      clone.tap do |query|
        if fields.empty?
          query.instance_variable_set(:@select_fields, ["#{table_name}.*"])
        else
          formatted_fields = fields.map do |field|
            case field
            when Symbol
              "#{table_name}.#{field}"
            when String
              field.include?('.') ? field : "#{table_name}.#{field}"
            else
              field.to_s
            end
          end
          query.instance_variable_set(:@select_fields, formatted_fields)
        end
      end
    end

    def select_raw(sql)
      clone.tap do |query|
        query.instance_variable_set(:@select_fields, [sql])
      end
    end

    # WHERE methods
    def where(conditions = nil, **kwargs, &block)
      clone.tap do |query|
        if block_given?
          # DSL block: where { name.eq("Alice").and(age.gt(18)) }
          dsl = WhereDSL.new(table_name, query.instance_variable_get(:@param_counter))
          condition = dsl.instance_eval(&block)
          query.add_where_condition(condition.to_sql, condition.params)
        elsif conditions.is_a?(Hash) || !kwargs.empty?
          # Hash conditions: where(name: "Alice", age: 25)
          hash_conditions = conditions.is_a?(Hash) ? conditions : kwargs
          query.add_hash_conditions(hash_conditions)
        elsif conditions.is_a?(String)
          # Raw SQL: where("name = ? AND age > ?", "Alice", 18)
          query.add_where_condition(conditions, [])
        end
      end
    end

    def where_raw(sql, *params)
      clone.tap do |query|
        query.add_where_condition(sql, params)
      end
    end

    # JOIN methods
    def join(table, condition = nil, **kwargs)
      add_join("INNER JOIN", table, condition, kwargs)
    end

    def left_join(table, condition = nil, **kwargs)
      add_join("LEFT JOIN", table, condition, kwargs)
    end

    def right_join(table, condition = nil, **kwargs)
      add_join("RIGHT JOIN", table, condition, kwargs)
    end

    def inner_join(table, condition = nil, **kwargs)
      add_join("INNER JOIN", table, condition, kwargs)
    end

    # GROUP BY and HAVING
    def group_by(*fields)
      clone.tap do |query|
        formatted_fields = fields.map { |f| format_field(f) }
        query.instance_variable_set(:@group_by_fields, 
          query.instance_variable_get(:@group_by_fields) + formatted_fields)
      end
    end

    def having(condition, *params)
      clone.tap do |query|
        query.instance_variable_get(:@having_conditions) << [condition, params]
        query.instance_variable_set(:@param_counter, 
          query.instance_variable_get(:@param_counter) + params.length)
      end
    end

    # ORDER BY
    def order_by(*fields)
      clone.tap do |query|
        formatted_fields = fields.map do |field|
          case field
          when Hash
            field.map { |f, direction| "#{format_field(f)} #{direction.to_s.upcase}" }.join(', ')
          else
            format_field(field)
          end
        end
        query.instance_variable_set(:@order_by_fields, formatted_fields)
      end
    end

    def order(field, direction = :asc)
      order_by(field => direction)
    end

    # LIMIT and OFFSET
    def limit(count)
      clone.tap do |query|
        query.instance_variable_set(:@limit_value, count)
      end
    end

    def offset(count)
      clone.tap do |query|
        query.instance_variable_set(:@offset_value, count)
      end
    end

    # Pagination helpers
    def page(page_num, per_page = 20)
      offset_count = (page_num - 1) * per_page
      limit(per_page).offset(offset_count)
    end

    # Execution methods
    def to_sql
      build_sql
    end

    def to_a
      execute.value_or([])
    end

    def first
      limit(1).execute.bind do |results|
        result = results.first
        result ? Result.success(result) : Result.failure("No records found")
      end
    end

    def count
      select_raw("COUNT(*) as count")
        .limit(nil)
        .offset(nil)
        .execute
        .map { |results| results.first&.[]('count')&.to_i || 0 }
    end

    def exists?
      select_raw("1")
        .limit(1)
        .execute
        .map { |results| !results.empty? }
    end

    def execute
      Result.try do
        sql, params = build_sql_with_params
        result = Database.query(sql, params)
        
        case result
        when ->(r) { r.respond_to?(:map) }
          result.map { |row| row_to_data(row) }
        else
          [row_to_data(result)]
        end
      end
    end

    # Aggregation methods
    def sum(field)
      select_raw("SUM(#{format_field(field)}) as sum")
        .execute
        .map { |results| results.first&.[]('sum')&.to_f || 0 }
    end

    def avg(field)
      select_raw("AVG(#{format_field(field)}) as avg")
        .execute
        .map { |results| results.first&.[]('avg')&.to_f || 0 }
    end

    def max(field)
      select_raw("MAX(#{format_field(field)}) as max")
        .execute
        .map { |results| results.first&.[]('max') }
    end

    def min(field)
      select_raw("MIN(#{format_field(field)}) as min")
        .execute
        .map { |results| results.first&.[]('min') }
    end

    private

    def clone
      Marshal.load(Marshal.dump(self))
    end

    def add_join(join_type, table, condition, kwargs)
      clone.tap do |query|
        if condition
          join_clause = "#{join_type} #{table} ON #{condition}"
        elsif kwargs.any?
          # Auto-generate join condition from kwargs
          conditions = kwargs.map do |local_field, foreign_field|
            "#{table_name}.#{local_field} = #{table}.#{foreign_field}"
          end.join(' AND ')
          join_clause = "#{join_type} #{table} ON #{conditions}"
        else
          raise ArgumentError, "Join requires either condition or field mapping"
        end
        
        query.instance_variable_get(:@joins) << join_clause
      end
    end

    def add_where_condition(condition, params)
      @where_conditions << [condition, params]
      @param_counter += params.length
    end

    def add_hash_conditions(hash)
      hash.each do |field, value|
        if value.is_a?(Array)
          placeholders = value.map { next_placeholder }.join(', ')
          add_where_condition("#{format_field(field)} IN (#{placeholders})", value)
        elsif value.is_a?(Range)
          add_where_condition(
            "#{format_field(field)} BETWEEN #{next_placeholder} AND #{next_placeholder}",
            [value.begin, value.end]
          )
        elsif value.nil?
          add_where_condition("#{format_field(field)} IS NULL", [])
        else
          add_where_condition("#{format_field(field)} = #{next_placeholder}", [value])
        end
      end
    end

    def format_field(field)
      case field
      when Symbol
        "#{table_name}.#{field}"
      when String
        field.include?('.') ? field : "#{table_name}.#{field}"
      else
        field.to_s
      end
    end

    def next_placeholder
      @param_counter += 1
      "$#{@param_counter}"
    end

    def build_sql_with_params
      sql = build_sql
      params = collect_params
      [sql, params]
    end

    def build_sql
      parts = []
      
      parts << "SELECT #{@select_fields.join(', ')}"
      parts << "FROM #{table_name}"
      parts.concat(@joins) if @joins.any?
      
      if @where_conditions.any?
        where_clause = @where_conditions.map { |condition, _| condition }.join(' AND ')
        parts << "WHERE #{where_clause}"
      end
      
      parts << "GROUP BY #{@group_by_fields.join(', ')}" if @group_by_fields.any?
      
      if @having_conditions.any?
        having_clause = @having_conditions.map { |condition, _| condition }.join(' AND ')
        parts << "HAVING #{having_clause}"
      end
      
      parts << "ORDER BY #{@order_by_fields.join(', ')}" if @order_by_fields.any?
      parts << "LIMIT #{@limit_value}" if @limit_value
      parts << "OFFSET #{@offset_value}" if @offset_value
      
      parts.join(' ')
    end

    def collect_params
      params = []
      @where_conditions.each { |_, condition_params| params.concat(condition_params) }
      @having_conditions.each { |_, condition_params| params.concat(condition_params) }
      params
    end

    def row_to_data(row)
      return row unless @data_class && @select_fields == ["#{table_name}.*"]
      
      attrs = {}
      @data_class.members.each do |col|
        attrs[col] = deserialize_value(col, row[col.to_s])
      end
      @data_class.new(**attrs)
    end

    def deserialize_value(column, value)
      return nil if value.nil?
      
      case column
      when :id, /.*_id$/
        value.to_i
      when :created_at, :updated_at
        Time.parse(value.to_s)
      else
        value
      end
    end
  end

  # DSL for building WHERE conditions
  class WhereDSL
    attr_reader :params

    def initialize(table_name, param_counter)
      @table_name = table_name
      @param_counter = param_counter
      @params = []
    end

    def method_missing(field_name, *args)
      FieldCondition.new(field_name, @table_name, self)
    end

    def add_param(value)
      @params << value
      @param_counter += 1
      "$#{@param_counter}"
    end

    class FieldCondition
      def initialize(field, table_name, dsl)
        @field = field
        @table_name = table_name
        @dsl = dsl
      end

      def eq(value)
        Condition.new("#{@table_name}.#{@field} = #{@dsl.add_param(value)}", @dsl.params.dup)
      end

      def ne(value)
        Condition.new("#{@table_name}.#{@field} != #{@dsl.add_param(value)}", @dsl.params.dup)
      end

      def gt(value)
        Condition.new("#{@table_name}.#{@field} > #{@dsl.add_param(value)}", @dsl.params.dup)
      end

      def gte(value)
        Condition.new("#{@table_name}.#{@field} >= #{@dsl.add_param(value)}", @dsl.params.dup)
      end

      def lt(value)
        Condition.new("#{@table_name}.#{@field} < #{@dsl.add_param(value)}", @dsl.params.dup)
      end

      def lte(value)
        Condition.new("#{@table_name}.#{@field} <= #{@dsl.add_param(value)}", @dsl.params.dup)
      end

      def like(pattern)
        Condition.new("#{@table_name}.#{@field} LIKE #{@dsl.add_param(pattern)}", @dsl.params.dup)
      end

      def in(values)
        placeholders = values.map { |v| @dsl.add_param(v) }.join(', ')
        Condition.new("#{@table_name}.#{@field} IN (#{placeholders})", @dsl.params.dup)
      end

      def null
        Condition.new("#{@table_name}.#{@field} IS NULL", @dsl.params.dup)
      end

      def not_null
        Condition.new("#{@table_name}.#{@field} IS NOT NULL", @dsl.params.dup)
      end
    end

    class Condition
      attr_reader :sql, :params

      def initialize(sql, params)
        @sql = sql
        @params = params
      end

      def and(other_condition)
        combined_params = @params + other_condition.params
        Condition.new("(#{@sql}) AND (#{other_condition.sql})", combined_params)
      end

      def or(other_condition)
        combined_params = @params + other_condition.params
        Condition.new("(#{@sql}) OR (#{other_condition.sql})", combined_params)
      end

      def to_sql
        @sql
      end
    end
  end
end