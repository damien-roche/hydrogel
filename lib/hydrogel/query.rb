module Hydrogel
  class Query
    include Enumerable

    ATTRS = [:filter, :filtered, :query, :fields, :sort, :functions].freeze
    ANOTHER_ATTRS = [:size, :facets, :aggs, :no_fields, :index, :type, :multi_match, :functions, :score_mode, :page,
                     :per_page, :from, :size, :klass].freeze

    BOOL_OPS = [:must, :should, :must_not].freeze
    ROOT_OPS = [:and, :or, :not].freeze
    ALL_OPS = BOOL_OPS + ROOT_OPS
    OP = :_op

    ATTRS.each { |attr| attr_reader attr }

    def initialize(klass, options = {})
      @klass = klass
      @index = klass.index_name
      @type = klass.document_type
      @size = nil
      ATTRS.each { |arg| instance_variable_set("@#{arg}", []) }
      @facets = {}
      @aggs = {}
      @no_fields = false
      add_scopes(options)
    end

    class << self
      def add_scope(klass, name, scope)
        (scopes[klass] ||= {})[name.to_sym] = scope
      end

      def add_default_scope(klass, scope)
        default_scopes[klass] = scope
      end

      def scopes
        @scopes ||= {}
      end

      def default_scopes
        scopes[:default] ||= {}
      end
    end

    def each(&block)
      result.each { |record| block.call(record) }
    end

    def result(options = {})
      @result = @klass.h_search(*RequestBuilder.new(self).build(options))
    end

    # =============  global
    def filter(args)
      @filter += prepare_arguments(args)
      self
    end

    def query(args)
      @query = [] if has_match_all?
      @query += prepare_arguments(args)
      self
    end

    def filtered(args)
      @filtered += prepare_arguments(args)
      self
    end

    def facets(args)
      @facets.merge!(args)
      self
    end

    def aggs(args)
      @aggs.merge!(args)
      self
    end

    def multi_match(query, fields, options = {})
      @multi_match = { query: query, fields: fields }.merge(options)
      self
    end

    def function_score(score_mode = nil, args)
      if args.is_a? Hash
        @functions << args
      elsif args.is_a? Array
        @functions += args
      end
      @score_mode = score_mode
      self
    end

    # =============  shortcuts

    [:terms, :term, :ids, :range].each do |shortcut|
      define_method(shortcut) do |location = :filtered, args|
        add_argument_by_method(args, shortcut, location)
        self
      end
    end

    [:match, :common, :prefix, :wildcard, :regexp, :fuzzy].each do |shortcut|
      define_method(shortcut) do |location = :query, args|
        add_argument_by_method(args, shortcut, location)
        self
      end
    end
    # ==================

    def count
      @size = 0
      pure_request['hits']['total']
    end

    def many
      @size = Config.many_size
      self
    end

    def match_all
      @query = prepare_arguments(match_all: {})
      self
    end

    def pluck(*args)
      fields(*args)
      pure_request(extract: :fields)
    end

    def index(*value)
      @index = value
      self
    end

    def type(*value)
      @type = value
      self
    end

    def page(value)
      @page = value
      self
    end

    def per_page(value)
      @per_page = value
      self
    end

    def fields(*args)
      @no_fields = false
      @fields += args
      self
    end

    def no_fields
      @no_fields = true
      @fields = []
      self
    end

    def from(value)
      @from = value
      self
    end

    def size(value)
      @size = value
      self
    end

    def sort_by(args)
      @sort += to_array_hash(args)
      self
    end

    # shortcut for sort_by
    def order(args)
      @sort += args.map { |k, v| { k => { order: v } } }
      self
    end

    %w(records results to_a total first last).each do |method|
      define_method(method) do
        result.send(method)
      end
    end

    private

    def has_match_all?
      @query[0] && @query[0][:match_all]
    end

    def add_scopes(options)
      (Query.scopes[@klass] || {}).each { |name, body| define_singleton_method(name, body) }
      self.instance_exec(&Query.default_scopes[@klass]) if !options[:unscoped] && Query.default_scopes[@klass]
    end

    def operator(hash)
      hash[Hydrogel::Query::OP]
    end

    alias_method :op, :operator

    def add_argument_by_method(args, operator, method_name = nil)
      new_args = { operator => reject_operator(args), OP => op(args) }
      send(method_name, new_args) if [:filtered, :filter, :query].include?(method_name.to_sym)
    end

    def prepare_arguments(hash)
      if hash.is_a? Array
        hash.map { |el| el.merge(operator: nil) }
      else
        reject_operator(hash).map { |k, v| { k => v, operator: op(hash) } }
      end
    end

    def prepare_arguments_with_matcher(hash, matcher)
      reject_operator(hash).map { |k, v| { matcher => { k => v }, operator: op(hash) } }
    end

    def reject_operator(hash)
      hash.reject { |k, _| k == OP }
    end

    def to_array_hash(hash)
      hash.map { |k, v| { k => v } }
    end

    def pure_request(options = {})
      ::Hydrogel.h_search(*RequestBuilder.new(self).build(options.merge(index: @index, type: @type)))
    end
  end
end
