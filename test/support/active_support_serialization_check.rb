# frozen_string_literal: true

# Run in a subprocess to check DataSerializer with ActiveSupport and
# ActiveRecord loaded, which the unit suite deliberately does not load.
# ActiveSupport adds as_json to Object and to many core classes; the check
# confirms the serializer still rejects the generic ones and accepts the
# deliberate ones.
#
# Prints "OK" and exits 0 on success, prints "SKIP: ..." and exits 0 when
# ActiveSupport or ActiveRecord (with sqlite3) cannot be loaded, and raises
# otherwise. To run it, use a bundle that has activerecord and sqlite3:
#
#   BUNDLE_GEMFILE=/path/to/Gemfile bundle exec ruby -Ilib test/support/active_support_serialization_check.rb

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

begin
  require "active_support"
  require "active_support/time"
  require "active_record"
  require "sqlite3"
rescue LoadError => e
  puts "SKIP: ActiveSupport, ActiveRecord or sqlite3 is not available (#{e.message})"
  exit 0
end

require "bigdecimal"
require "set"
require "stringio"
require "typst_rails/renderer"

def check(description)
  raise "Check failed: #{description}" unless yield
end

def normalize(value, path: "locals.value")
  TypstRails::DataSerializer.normalize(value, path: path)
end

def rejects(value, fragment)
  normalize(value)
  raise "Check failed: #{value.class} should not serialize"
rescue TypstRails::SerializationError => e
  raise "Check failed: #{value.class} error was #{e.message.inspect}" unless e.message.include?(fragment)
end

# The fallback this gem has to see through.
fallback = Object.instance_method(:as_json)
check("Object#as_json comes from ActiveSupport") do
  fallback.source_location.first.end_with?("active_support/core_ext/object/json.rb")
end

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table(:widgets) do |t|
    t.string :name
    t.decimal :price, precision: 8, scale: 2
  end
end

class Widget < ActiveRecord::Base; end
Widget.create!(name: "Sprocket", price: BigDecimal("1.50"))

# Generic as_json, which would write {} or instance variables: rejected.
poro = Class.new do
  def initialize
    @secret = 1
  end
end
rejects(poro.new, "which is not JSON-serializable")
rejects(-> {}, "is a Proc")
rejects(Object.new.method(:to_s), "is a Method")
rejects($stdout, "is an IO")
rejects(Rational(1, 3), "is a Rational")
rejects(Float::NAN, "is NaN")
rejects(Enumerator.new { |y| loop { y << 1 } }, "is an Enumerator")

# Deliberate as_json, including ActiveRecord's.
check("models use ActiveModel's as_json") do
  normalize(Widget.first) == { "id" => 1, "name" => "Sprocket", "price" => "1.5" }
end
check("relations use ActiveRecord's as_json") do
  normalize(Widget.all) == [{ "id" => 1, "name" => "Sprocket", "price" => "1.5" }]
end

# Types with explicit rules.
Time.zone = "Eastern Time (US & Canada)"
zoned = Time.zone.local(2024, 3, 9, 8, 30, 15)
check("TimeWithZone becomes ISO 8601") { normalize(zoned) == "2024-03-09T08:30:15-05:00" }
check("BigDecimal becomes a decimal string") { normalize(BigDecimal("19.99")) == "19.99" }
check("Set becomes an Array") { normalize(Set[:a]) == ["a"] }
check("Symbol becomes a String") { normalize(:a) == "a" }

# Struct and Data use to_h, so their members are checked rather than passed
# through ActiveSupport's fallback.
point = Struct.new(:x, :y)
check("Struct becomes a Hash") { normalize(point.new(1, 2)) == { "x" => 1, "y" => 2 } }
rejects(point.new(-> {}, 2), "locals.value.x is a Proc")
if RUBY_VERSION >= "3.2"
  coordinate = Data.define(:lat)
  check("Data becomes a Hash") { normalize(coordinate.new(lat: 1.5)) == { "lat" => 1.5 } }
end

# The renderer writes what the serializer returns, not ActiveSupport's encoding.
renderer = TypstRails::Renderer.new('#let data = json("typst_data.json")')
view = Struct.new(:assigns).new({ "widget" => Widget.first, "exporter" => poro.new })
original_stderr = $stderr
$stderr = StringIO.new
begin
  data = renderer.send(:collect_data_for_typst, view, { at: zoned })
  err = $stderr.string
ensure
  $stderr = original_stderr
end
check("the model reaches the data") { data[:widget] == { "id" => 1, "name" => "Sprocket", "price" => "1.5" } }
check("the PORO instance variable is left out") { !data.key?(:exporter) }
check("the warning names it") { err.include?("@exporter (@exporter is a") }
check("the local is converted") { data[:at] == "2024-03-09T08:30:15-05:00" }

puts "OK"
