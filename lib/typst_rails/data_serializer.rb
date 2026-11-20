# frozen_string_literal: true

require "date"
require "set"

module TypstRails
  # Base class for errors raised by TypstRails. Defined fully in
  # typst_rails/renderer; declared here so this file can be loaded alone.
  class Error < StandardError; end

  # Raised when data bound for typst_data.json contains a value that has no
  # faithful JSON form. It is a {TypstRails::Error}, so code that already
  # rescues render failures handles it too.
  #
  # @example
  #   begin
  #     renderer.render(nil, { total: Money.new(100) })
  #   rescue TypstRails::SerializationError => e
  #     e.path   #=> "locals.total"
  #     e.reason #=> "is a Money, which is not JSON-serializable"
  #   end
  class SerializationError < Error
    # @return [String] Where the value sits, such as "locals.items[0].amount"
    attr_reader :path

    # @return [String] What is wrong with the value, without the path or hint
    attr_reader :reason

    # @param path [String] Where the value sits in the data
    # @param reason [String] What is wrong with the value
    # @param hint [String, nil] How to fix it, appended to the message
    def initialize(path, reason, hint = nil)
      @path = path
      @reason = reason
      super([summary, hint].compact.join(" "))
    end

    # @return [String] The path and reason, without the hint
    def summary
      "#{path} #{reason}."
    end
  end

  # Converts Ruby values into plain JSON data (Hash with String keys, Array,
  # String, Integer, finite Float, true, false, nil) for typst_data.json.
  #
  # Encoding the value with to_json directly is not safe: any object responds
  # to it, so a value with no sensible JSON form still produces output. Plain
  # JSON writes the object's #to_s, and ActiveSupport's Object#as_json writes
  # its instance variables, so the template quietly receives "#<Money...>" or
  # {} instead of an error. This class accepts only values it can convert
  # faithfully and raises {SerializationError}, naming the key path, for the
  # rest.
  #
  # Conversion rules:
  # - nil, true, false, Integer and String pass through. A String must be
  #   valid UTF-8 (a binary String holding valid UTF-8 bytes is relabeled).
  # - Symbol becomes a String.
  # - A finite Float passes through; NaN and Infinity raise.
  # - BigDecimal becomes a String, such as "19.99", to keep its exact value.
  #   This matches ActiveSupport, so a decimal column reads the same whether it
  #   arrives bare or inside a model. In Typst, use decimal(data.total) or
  #   float(data.total).
  # - Other Numerics (Rational, Complex) raise.
  # - Time, Date, DateTime and ActiveSupport::TimeWithZone become ISO 8601
  #   strings, without fractional seconds.
  # - Hash keys must be Strings, Symbols or Numerics, and become Strings.
  #   Values are converted recursively.
  # - Array and Set elements are converted recursively.
  # - Any other object is converted with #as_json when its class defines one
  #   deliberately, or else with #to_h when its class defines that, and the
  #   result is converted recursively. The generic as_json that ActiveSupport
  #   puts on Object, and the ones on Kernel, BasicObject, Enumerable, IO and
  #   Numeric, do not count. Struct and Data use #to_h, because ActiveSupport's
  #   as_json for them would pass their members through the generic fallback.
  # - Anything else raises.
  #
  # @example
  #   TypstRails::DataSerializer.normalize({ due: Date.new(2024, 3, 9), tags: Set[:a] })
  #   #=> { "due" => "2024-03-09", "tags" => ["a"] }
  class DataSerializer
    # Owners of #as_json that do not show a deliberate JSON form. Object holds
    # ActiveSupport's fallback (active_support/core_ext/object/json), which
    # dumps instance variables. ActiveSupport also defines as_json on
    # Enumerable (to_a, which never ends for an endless Enumerator), IO (its
    # #to_s), Numeric (self, so Rational stays Rational), Struct and Data.
    # Ruby 2.7 still has the old, deprecated ::Data, which warns when named.
    IGNORED_AS_JSON_OWNERS = [Object, Kernel, BasicObject, Enumerable, IO, Numeric, Struct,
                              (::Data if RUBY_VERSION >= "3.2")].compact.freeze

    # Owners of #to_h that do not show a deliberate Hash form. Enumerable#to_h
    # works only on pairs and would enumerate an IO or Enumerator.
    IGNORED_TO_H_OWNERS = [Object, Kernel, BasicObject, Enumerable].freeze

    # Nesting limit, so a #to_h or #as_json that returns a fresh object every
    # time cannot recurse until the stack overflows.
    MAX_DEPTH = 100

    # Default advice appended to errors about unsupported objects.
    CONVERT_HINT = "Convert it to a String, Number, Hash, or Array before rendering, " \
                   "or define as_json or to_h on its class to return plain data."

    # Keys that can be written after a dot in a key path.
    PLAIN_KEY = /\A[A-Za-z_][A-Za-z0-9_]*\z/.freeze

    # Converts +value+ into plain JSON data.
    #
    # @param value [Object] The value to convert
    # @param path [String] The name used for +value+ in error messages
    # @return [Object] Plain JSON data
    # @raise [SerializationError] if +value+, or anything inside it, has no
    #   faithful JSON form
    def self.normalize(value, path: "data")
      new.normalize(value, path)
    end

    # Extends a key path with a Hash key.
    #
    # @param path [String] The path of the Hash
    # @param key [Object] The key
    # @return [String] e.g. "locals.title" or 'locals["first name"]'
    def self.child_path(path, key)
      name = key.to_s
      name.match?(PLAIN_KEY) ? "#{path}.#{name}" : "#{path}[#{name.inspect}]"
    end

    def initialize
      @in_progress = {}.compare_by_identity
    end

    # @param value [Object] The value to convert
    # @param path [String] The name used for +value+ in error messages
    # @param depth [Integer] Current nesting depth
    # @return [Object] Plain JSON data
    # @raise [SerializationError] if the value has no faithful JSON form
    def normalize(value, path, depth = 0)
      raise SerializationError.new(path, "is nested more than #{MAX_DEPTH} levels deep") if depth > MAX_DEPTH

      case value
      when nil, true, false, Integer then value
      when String then normalize_string(value, path)
      when Symbol then value.to_s
      when Float then normalize_float(value, path)
      when Hash then guard_cycle(value, path) { normalize_hash(value, path, depth) }
      when Array, Set then guard_cycle(value, path) { normalize_list(value, path, depth) }
      else normalize_other(value, path, depth)
      end
    end

    private

    def normalize_string(value, path)
      return value if value.encoding == Encoding::UTF_8 && value.valid_encoding?

      utf8 = to_utf8(value)
      return utf8 if utf8

      raise SerializationError.new(path, "is a String in #{value.encoding} that has no valid UTF-8 form",
                                   "Fix its encoding with String#encode or String#scrub.")
    end

    # Binary strings are relabeled rather than transcoded, so UTF-8 bytes read
    # with File.binread still pass, as they did with to_json.
    def to_utf8(value)
      if value.encoding == Encoding::BINARY
        relabeled = value.dup.force_encoding(Encoding::UTF_8)
        relabeled if relabeled.valid_encoding?
      elsif value.valid_encoding?
        value.encode(Encoding::UTF_8)
      end
    rescue EncodingError
      nil
    end

    def normalize_list(list, path, depth)
      list.each_with_index.map { |item, index| normalize(item, "#{path}[#{index}]", depth + 1) }
    end

    def normalize_float(value, path)
      return value if value.finite?

      raise SerializationError.new(path, "is #{value}, which JSON cannot represent",
                                   "Replace it with nil or a finite number.")
    end

    def normalize_hash(hash, path, depth)
      hash.each_with_object({}) do |(key, value), result|
        name = hash_key(key, path)
        if result.key?(name)
          raise SerializationError.new(path, "has more than one key that becomes #{name.inspect} in JSON",
                                       "Keep only one of them.")
        end

        result[name] = normalize(value, self.class.child_path(path, name), depth + 1)
      end
    end

    def hash_key(key, path)
      case key
      when String, Symbol, Numeric then key.to_s
      else
        raise SerializationError.new(path, "has a key that is #{a_class_name(key)}, but JSON object keys " \
                                           "must be Strings, Symbols, or Numbers", "Convert the key to a String.")
      end
    end

    def normalize_other(value, path, depth)
      unless Kernel === value # rubocop:disable Style/CaseEquality -- BasicObject has no #is_a?
        raise SerializationError.new(path, "is a BasicObject, which is not JSON-serializable", CONVERT_HINT)
      end

      return value.iso8601 if time_like?(value)
      return normalize_big_decimal(value, path) if big_decimal?(value)

      if value.is_a?(Numeric)
        raise SerializationError.new(path, "is #{a_class_name(value)}, which JSON cannot represent exactly",
                                     "Convert it to an Integer, Float, or BigDecimal.")
      end

      converter = converter_for(value)
      unless converter
        raise SerializationError.new(path, "is #{a_class_name(value)}, which is not JSON-serializable", CONVERT_HINT)
      end

      guard_cycle(value, path) { normalize(convert(value, converter, path), path, depth + 1) }
    end

    # ActiveSupport::TimeWithZone is not a Time subclass, but its #is_a?
    # answers true for Time, which `case`/`when` would not consult.
    def time_like?(value)
      value.is_a?(Time) || value.is_a?(Date)
    end

    def big_decimal?(value)
      defined?(::BigDecimal) && value.is_a?(::BigDecimal)
    end

    def normalize_big_decimal(value, path)
      return value.to_s("F") if value.finite?

      raise SerializationError.new(path, "is a BigDecimal #{value}, which JSON cannot represent",
                                   "Replace it with nil or a finite number.")
    end

    def converter_for(value)
      if defined_by_class?(value, :as_json, IGNORED_AS_JSON_OWNERS)
        :as_json
      elsif defined_by_class?(value, :to_h, IGNORED_TO_H_OWNERS)
        :to_h
      end
    end

    def defined_by_class?(value, name, ignored_owners)
      value.respond_to?(name) && !ignored_owners.include?(value.method(name).owner)
    rescue NameError
      false
    end

    def convert(value, converter, path)
      result = value.public_send(converter)
      if result.equal?(value)
        raise SerializationError.new(path, "is #{a_class_name(value)} whose #{converter} returns itself")
      end

      result
    rescue SerializationError
      raise
    rescue StandardError => e
      raise SerializationError.new(path, "is #{a_class_name(value)} whose #{converter} raised #{e.class}: #{e.message}")
    end

    def guard_cycle(value, path)
      raise SerializationError.new(path, "contains itself, which JSON cannot represent") if @in_progress.key?(value)

      @in_progress[value] = true
      begin
        yield
      ensure
        @in_progress.delete(value)
      end
    end

    # @return [String] e.g. "a Money" or "an Object"
    def a_class_name(value)
      name = class_name(value)
      "#{name.match?(/\A[AEIOU]/) ? "an" : "a"} #{name}"
    end

    def class_name(value)
      klass = value.class
      klass.name || klass.inspect
    end
  end
end
