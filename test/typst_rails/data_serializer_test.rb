# frozen_string_literal: true

require "test_helper"
require "English"
require "stringio"

module TypstRails
  # Unit tests for DataSerializer without ActiveSupport, which this suite does
  # not load. test/support/active_support_serialization_check.rb covers the
  # same rules with ActiveSupport and ActiveRecord loaded.
  class DataSerializerTest < Minitest::Test
    Point = Struct.new(:x, :y)

    # A value object with no JSON form, like a Money from a gem.
    class Money
      def initialize(cents)
        @cents = cents
      end
    end

    class Report
      def initialize(title)
        @title = title
      end

      def as_json(*)
        { title: @title, generated: Date.new(2024, 1, 2) }
      end
    end

    class Settings
      def to_h
        { theme: :dark }
      end
    end

    def normalize(value, path: "data")
      DataSerializer.normalize(value, path: path)
    end

    def assert_unserializable(value, path: "data", reason: nil)
      error = assert_raises(SerializationError) { normalize(value, path: path) }
      assert_includes error.reason, reason if reason
      error
    end

    # MARK: - Primitives

    def test_json_primitives_pass_through
      [nil, true, false, 0, -7, 2**70, 1.5, "text", ""].each do |value|
        value.nil? ? assert_nil(normalize(value)) : assert_equal(value, normalize(value))
      end
    end

    def test_strings_are_returned_without_copying
      value = "text"

      assert_same value, normalize(value)
    end

    def test_symbols_become_strings
      assert_equal "draft", normalize(:draft)
    end

    # MARK: - Strings and encodings

    def test_invalid_utf8_raises
      error = assert_unserializable(+"bad \xFF byte", reason: "has no valid UTF-8 form")

      assert_includes error.message, "String#scrub"
    end

    def test_binary_strings_holding_utf8_are_relabeled
      result = normalize("café".b)

      assert_equal "café", result
      assert_equal Encoding::UTF_8, result.encoding
    end

    def test_binary_strings_that_are_not_utf8_raise
      assert_unserializable("\xFF\xFE".b, reason: "ASCII-8BIT")
    end

    def test_strings_in_other_encodings_are_transcoded
      result = normalize("café".encode(Encoding::ISO_8859_1))

      assert_equal "café", result
      assert_equal Encoding::UTF_8, result.encoding
    end

    def test_strings_with_no_utf8_form_raise
      broken = "\x81".dup.force_encoding(Encoding::Shift_JIS)

      assert_unserializable(broken, reason: "Shift_JIS")
    end

    # UTF-7 is a dummy encoding: its bytes are "valid", but Ruby cannot
    # transcode it.
    def test_strings_ruby_cannot_transcode_raise
      assert_unserializable("+AGEAYgBj-".dup.force_encoding(Encoding::UTF_7), reason: "UTF-7")
    end

    # MARK: - Numbers

    def test_nan_and_infinity_raise
      [Float::NAN, Float::INFINITY, -Float::INFINITY].each do |value|
        error = assert_unserializable(value, reason: "which JSON cannot represent")

        assert_includes error.message, "finite number"
      end
    end

    def test_big_decimals_become_plain_decimal_strings
      require_big_decimal!

      assert_equal "19.99", normalize(BigDecimal("19.99"))
      assert_equal "100000000000000000000.000000000000000001", normalize(BigDecimal("1e20") + BigDecimal("1e-18"))
    end

    def test_non_finite_big_decimals_raise
      require_big_decimal!

      assert_unserializable(BigDecimal("NaN"), reason: "BigDecimal NaN")
    end

    # bigdecimal is a bundled gem from Ruby 3.4, so it may not be loadable
    # under this bundle. A stand-in exercises the same rule.
    def test_the_big_decimal_rule_with_a_stand_in
      stand_in = Class.new do
        def initialize(text, finite: true)
          @text = text
          @finite = finite
        end

        def finite?
          @finite
        end

        def to_s(format = nil)
          format == "F" ? @text : "0.#{@text}e1"
        end
      end

      with_defined_constant(:BigDecimal, stand_in) do
        assert_equal "1.5", normalize(stand_in.new("1.5"))
        assert_unserializable(stand_in.new("Infinity", finite: false), reason: "is a BigDecimal")
      end
    end

    def test_rationals_and_complex_numbers_raise
      assert_unserializable(Rational(1, 3), reason: "is a Rational")
      assert_unserializable(Complex(1, 2), reason: "is a Complex")
    end

    # MARK: - Dates and times

    def test_dates_become_iso8601
      assert_equal "2024-03-09", normalize(Date.new(2024, 3, 9))
      assert_equal "2024-03-09T08:30:15+00:00", normalize(DateTime.new(2024, 3, 9, 8, 30, 15))
    end

    # Fractional seconds are dropped, as the renderer always did for Times.
    def test_times_become_iso8601_with_their_offset
      assert_equal "2024-03-09T08:30:15Z", normalize(Time.utc(2024, 3, 9, 8, 30, 15.5))
      assert_equal "2024-03-09T08:30:15+02:00", normalize(Time.new(2024, 3, 9, 8, 30, 15, "+02:00"))
    end

    # ActiveSupport::TimeWithZone is not a Time subclass but claims to be one
    # through #is_a?; anything that does so is treated as a Time.
    def test_objects_that_claim_to_be_times_become_iso8601
      time_like = Class.new do
        def is_a?(klass)
          klass == Time || super
        end

        def iso8601
          "2024-03-09T08:30:15-05:00"
        end
      end.new

      assert_equal "2024-03-09T08:30:15-05:00", normalize(time_like)
    end

    # MARK: - Hashes

    def test_hash_keys_become_strings
      result = normalize({ :sym => 1, "str" => 2, 3 => 3, 1.5 => 4 })

      assert_equal({ "sym" => 1, "str" => 2, "3" => 3, "1.5" => 4 }, result)
    end

    def test_hash_values_are_converted_recursively
      result = normalize({ due: Date.new(2024, 3, 9), nested: { status: :open } })

      assert_equal({ "due" => "2024-03-09", "nested" => { "status" => "open" } }, result)
    end

    def test_other_hash_keys_raise
      error = assert_unserializable({ [1, 2] => "pair" }, path: "locals.lookup", reason: "key that is an Array")

      assert_equal "locals.lookup", error.path
    end

    def test_keys_that_collide_as_strings_raise
      assert_unserializable({ :a => 1, "a" => 2 }, reason: "more than one key that becomes \"a\"")
    end

    def test_input_hashes_are_not_mutated
      input = { due: Date.new(2024, 3, 9) }

      normalize(input)

      assert_equal({ due: Date.new(2024, 3, 9) }, input)
    end

    # MARK: - Arrays and Sets

    def test_arrays_are_converted_recursively
      assert_equal [1, "a", "2024-03-09", [nil]], normalize([1, :a, Date.new(2024, 3, 9), [nil]])
    end

    def test_sets_become_arrays
      assert_equal %w[a b], normalize(Set[:a, :b])
    end

    # MARK: - Objects that define their own JSON form

    def test_objects_with_their_own_as_json_are_converted_through_it
      assert_equal({ "title" => "Q1", "generated" => "2024-01-02" }, normalize(Report.new("Q1")))
    end

    def test_objects_with_their_own_to_h_are_converted_through_it
      assert_equal({ "theme" => "dark" }, normalize(Settings.new))
    end

    def test_structs_become_hashes
      assert_equal({ "x" => 1, "y" => "2024-03-09" }, normalize(Point.new(1, Date.new(2024, 3, 9))))
    end

    def test_structs_report_unserializable_members_by_path
      error = assert_unserializable(Point.new(Money.new(1), 2), path: "locals.origin")

      assert_equal "locals.origin.x", error.path
    end

    def test_data_objects_become_hashes
      skip "Data requires Ruby 3.2" unless RUBY_VERSION >= "3.2"

      coordinate = Data.define(:lat, :lng)

      assert_equal({ "lat" => 1.5, "lng" => 2.5 }, normalize(coordinate.new(lat: 1.5, lng: 2.5)))
    end

    def test_open_structs_become_hashes
      require_ostruct!

      # OpenStruct is what is under test here.
      assert_equal({ "name" => "Ada" }, normalize(OpenStruct.new(name: "Ada"))) # rubocop:disable Style/OpenStructUse
    end

    # A struct that defines as_json itself is converted through that, not to_h.
    def test_an_as_json_defined_on_a_struct_wins_over_to_h
      labelled = Struct.new(:value) do
        def as_json(*)
          "value=#{value}"
        end
      end

      assert_equal "value=3", normalize(labelled.new(3))
    end

    def test_as_json_results_are_checked_too
      leaky = Class.new do
        def as_json(*)
          { amount: Money.new(5) }
        end
      end

      error = assert_unserializable(leaky.new, path: "locals.invoice")

      assert_equal "locals.invoice.amount", error.path
    end

    def test_as_json_returning_self_raises
      selfish = Class.new do
        def as_json(*)
          self
        end
      end

      assert_unserializable(selfish.new, reason: "whose as_json returns itself")
    end

    def test_as_json_that_raises_is_reported
      broken = Class.new do
        def as_json(*)
          raise "no database"
        end
      end

      assert_unserializable(broken.new, reason: "as_json raised RuntimeError: no database")
    end

    def test_to_h_that_keeps_returning_new_objects_hits_the_depth_limit
      nesting = Class.new do
        def to_h
          { child: self.class.new }
        end
      end

      assert_unserializable(nesting.new, reason: "nested more than #{DataSerializer::MAX_DEPTH} levels deep")
    end

    # MARK: - Objects with no JSON form

    def test_plain_objects_raise_with_the_class_name_and_a_hint
      error = assert_unserializable(Money.new(100), path: "locals.total")

      assert_equal "is a TypstRails::DataSerializerTest::Money, which is not JSON-serializable", error.reason
      assert_equal "locals.total #{error.reason}. #{DataSerializer::CONVERT_HINT}", error.message
    end

    def test_the_key_path_names_hash_keys_and_array_indexes
      value = { line_items: [{ amount: 1 }, { amount: Money.new(2) }] }

      error = assert_unserializable(value, path: "locals")

      assert_equal "locals.line_items[1].amount", error.path
    end

    def test_keys_that_are_not_identifiers_are_quoted_in_the_path
      error = assert_unserializable({ "first name" => Money.new(1) }, path: "locals")

      assert_equal 'locals["first name"]', error.path
    end

    def test_callables_raise
      assert_unserializable(-> {}, reason: "is a Proc")
      assert_unserializable(1.method(:+), reason: "is a Method")
    end

    def test_io_objects_raise
      assert_unserializable($stdout, reason: "is an IO")
      assert_unserializable(StringIO.new("text"), reason: "is a StringIO")
    end

    # Enumerable#to_h would walk an endless enumerator forever.
    def test_enumerators_raise_without_being_walked
      assert_unserializable(Enumerator.new { |y| loop { y << 1 } }, reason: "is an Enumerator")
    end

    # An object can claim to respond to as_json without having the method.
    def test_objects_that_only_claim_to_respond_are_not_trusted
      boaster = Class.new do
        def respond_to?(*)
          true
        end
      end.new

      assert_unserializable(boaster, reason: "which is not JSON-serializable")
    end

    def test_anonymous_classes_are_described_by_inspect
      error = assert_unserializable(Class.new.new)

      assert_match(/is a #<Class:0x\h+>/, error.reason)
    end

    def test_basic_objects_raise
      assert_unserializable(BasicObject.new, reason: "is a BasicObject")
    end

    def test_self_referencing_arrays_raise
      looped = [1]
      looped << looped

      assert_unserializable(looped, reason: "contains itself")
    end

    def test_self_referencing_hashes_raise
      looped = {}
      looped[:self] = looped

      error = assert_unserializable(looped, path: "locals")

      assert_equal "locals.self", error.path
    end

    # The same object twice is not a cycle.
    def test_repeated_values_are_not_mistaken_for_cycles
      shared = { a: 1 }

      assert_equal [{ "a" => 1 }, { "a" => 1 }], normalize([shared, shared])
    end

    # MARK: - Errors

    def test_serialization_errors_are_typst_rails_errors
      assert_operator SerializationError, :<, Error
    end

    def test_summary_omits_the_hint
      error = SerializationError.new("locals.x", "is bad", "Fix it.")

      assert_equal "locals.x is bad.", error.summary
      assert_equal "locals.x is bad. Fix it.", error.message
    end

    def test_child_path
      assert_equal "locals.title", DataSerializer.child_path("locals", :title)
      assert_equal "locals[\"2\"]", DataSerializer.child_path("locals", 2)
    end

    # MARK: - With ActiveSupport and ActiveRecord

    # Runs in a subprocess so ActiveSupport's core extensions stay out of this
    # suite. ActiveSupport is not a development dependency, so the check
    # skips when it cannot be loaded.
    def test_conversion_rules_hold_with_active_support_and_active_record
      script = File.expand_path("../support/active_support_serialization_check.rb", __dir__)
      lib_dir = File.expand_path("../../lib", __dir__)
      output = IO.popen([RbConfig.ruby, "-I", lib_dir, script], err: %i[child out], &:read)
      last_line = output.lines.last&.strip

      skip last_line if last_line&.start_with?("SKIP")

      assert_predicate $CHILD_STATUS, :success?, "Expected the ActiveSupport check to pass, got:\n#{output}"
      assert_equal "OK", last_line
    end

    private

    # ostruct leaves the default gems in Ruby 3.5.
    def require_ostruct!
      require "ostruct"
    rescue LoadError
      skip "ostruct is not available"
    end

    def require_big_decimal!
      require "bigdecimal"
    rescue LoadError
      skip "bigdecimal is not available"
    end
  end
end
