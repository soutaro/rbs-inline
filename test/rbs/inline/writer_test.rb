# frozen_string_literal: true

require "test_helper"

class RBS::Inline::WriterTest < Minitest::Test
  include RBS::Inline

  def translate(src, opt_in: true, &block)
    src = "# rbs_inline: enabled\n\n" + src
    uses, decls, rbs_decls = Parser.parse(Prism.parse(src, filepath: "a.rb"), opt_in: opt_in)
    Writer.write(uses, decls, rbs_decls, &block)
  end

  def test_method_type
    output = translate(<<~RUBY)
      class Foo
        # @rbs () -> String
        #: (String) -> Integer
        def foo(x = nil)
        end

        # @rbs x: Integer
        # @rbs foo: Symbol
        # @rbs bar: Integer?
        # @rbs return: void
        def f(x=0, foo:, bar: nil)
        end

        def g(x=0, foo:, bar: nil)
        end
      end
    RUBY

    assert_equal <<~RBS, output
      class Foo
        # @rbs () -> String
        # : (String) -> Integer
        def foo: () -> String
               | (String) -> Integer

        # @rbs x: Integer
        # @rbs foo: Symbol
        # @rbs bar: Integer?
        # @rbs return: void
        def f: (?Integer x, foo: Symbol, ?bar: Integer?) -> void

        def g: (?untyped x, foo: untyped, ?bar: untyped) -> untyped
      end
    RBS
  end

  def test_method_type__splat
    output = translate(<<~RUBY)
      class Foo
        def f(*x)
        end

        # @rbs *x: Integer
        def g(*x)
        end

        def h(*)
        end

        # @rbs *: String
        def i(*)
        end
      end
    RUBY

    assert_equal <<~RBS, output
      class Foo
        def f: (*untyped x) -> untyped

        # @rbs *x: Integer
        def g: (*Integer x) -> untyped

        def h: (*untyped) -> untyped

        # @rbs *: String
        def i: (*String) -> untyped
      end
    RBS
  end

  def test_method_type__double_splat
    output = translate(<<~RUBY)
      class Foo
        def f(**x)
        end

        # @rbs **x: Integer
        def g(**x)
        end

        def h(**)
        end

        # @rbs **: String
        def i(**)
        end
      end
    RUBY

    assert_equal <<~RBS, output
      class Foo
        def f: (**untyped x) -> untyped

        # @rbs **x: Integer
        def g: (**Integer x) -> untyped

        def h: (**untyped) -> untyped

        # @rbs **: String
        def i: (**String) -> untyped
      end
    RBS
  end

  def test_method_type__return_assertion
    output = translate(<<~RUBY)
      class Foo
        def to_s #: String
        end

        def foo(
            x,
            y
          ) #: void
        end

        def hoge x,
          y #: Integer
        end
      end
    RUBY

    assert_equal <<~RBS, output
      class Foo
        def to_s: () -> String

        def foo: (untyped x, untyped y) -> void

        def hoge: (untyped x, untyped y) -> Integer
      end
    RBS
  end

  def test_method_type__annotation
    output = translate(<<~RUBY)
      class Foo
        # @rbs %a(pure)
        # @rbs return: String?
        def f()
        end
      end
    RUBY

    assert_equal <<~RBS, output
      class Foo
        # @rbs %a(pure)
        # @rbs return: String?
        %a{pure}
        def f: () -> String?
      end
    RBS
  end

  def test_method__block
    output = translate(<<~RUBY)
      class Foo
        # @rbs &block: (String) [self: Symbol] -> Integer
        def foo(&block)
        end

        # @rbs &block: ? (String) [self: Symbol] -> Integer
        def bar(&block)
        end
      end
    RUBY

    assert_equal <<~RBS, output
      class Foo
        # @rbs &block: (String) [self: Symbol] -> Integer
        def foo: () { (String) [self: Symbol] -> Integer } -> untyped

        # @rbs &block: ? (String) [self: Symbol] -> Integer
        def bar: () ?{ (String) [self: Symbol] -> Integer } -> untyped
      end
    RBS
  end

  def test_method_type__kind
    output = translate(<<~RUBY)
      class Foo
        def self.f()
        end
      end
    RUBY

    assert_equal <<~RBS, output
      class Foo
        def self.f: () -> untyped
      end
    RBS
  end

  def test_method_type__module_function
    output = translate(<<~RUBY)
      module Foo
        def f()
        end

        def g()
        end
        module_function :g

        module_function

        def h()
        end
      end
    RUBY

    assert_equal <<~RBS, output
      module Foo
        def f: () -> untyped

        def self?.g: () -> untyped

        def self?.h: () -> untyped
      end
    RBS
  end

  def test_method_type__visibility
    output = translate(<<~RUBY)
      class Foo
        # @rbs return: String
        private def foo()
        end
      end
    RUBY

    assert_equal <<~RBS, output
      class Foo
        # @rbs return: String
        private def foo: () -> String
      end
    RBS
  end

  def test_method__alias
    output = translate(<<~RUBY)
      class Foo
        alias eql? ==

        # foo is an alias of bar
        alias :foo :bar

        class << self
          # self.baz is an alias of self.qux
          alias baz qux
        end
      end
    RUBY

    assert_equal <<~RBS, output
      class Foo
        alias eql? ==

        # foo is an alias of bar
        alias foo bar

        # self.baz is an alias of self.qux
        alias self.baz self.qux
      end
    RBS
  end

  def test_mixin
    output = translate(<<~RUBY)
      class Foo
        include Foo

        include Bar #[Integer, String]
      end
    RUBY

    assert_equal <<~RBS, output
      class Foo
        include Foo

        include Bar[Integer, String]
      end
    RBS
  end

  def test_skip
    output = translate(<<~RUBY)
      # @rbs skip
      class Foo
      end

      class Bar
        # @rbs skip
        def foo = false

        # @rbs skip
        include Foo
      end
    RUBY

    assert_equal <<~RBS, output
      class Bar
      end
    RBS
  end

  def test_class__super
    output = translate(<<~RUBY)
      class Foo
      end

      class Bar < Object
      end

      # @rbs inherits Array[String]
      class Baz < Array
      end

      class Baz2 < Array #[String]
      end
    RUBY

    assert_equal <<~RBS, output
      class Foo
      end

      class Bar < Object
      end

      # @rbs inherits Array[String]
      class Baz < Array[String]
      end

      class Baz2 < Array[String]
      end
    RBS
  end

  def test_module__decl
    output = translate(<<~RUBY)
      module Foo
        module Bar
        end
      end

      # @rbs skip
      module Baz
      end
    RUBY

    assert_equal <<~RBS, output
      module Foo
        module Bar
        end
      end
    RBS
  end

  def test_attributes__unannotated
    output = translate(<<~RUBY)
      class Hello
        attr_reader :foo, :foo2, "hoge".to_sym
        private attr_reader :foo3

        # Attribute of bar
        attr_writer :bar
        private attr_writer :bar2

        attr_accessor :baz
        private attr_accessor :baz2
      end
    RUBY

    assert_equal <<~RBS, output
      class Hello
        attr_reader foo: untyped

        attr_reader foo2: untyped

        private attr_reader foo3: untyped

        # Attribute of bar
        attr_writer bar: untyped

        private attr_writer bar2: untyped

        attr_accessor baz: untyped

        private attr_accessor baz2: untyped
      end
    RBS
  end

  def test_attributes__typed
    output = translate(<<~RUBY)
      class Hello
        attr_reader :foo, :foo2, "hoge".to_sym #: String
        private attr_reader :foo3 #: String

        # Attribute of bar
        attr_writer :bar #: Array[Integer]
        private attr_writer :bar2 #: Array[Integer]

        attr_accessor :baz #: Integer |
        private attr_accessor :baz2 #: Integer
      end
    RUBY

    assert_equal <<~RBS, output
      class Hello
        attr_reader foo: String

        attr_reader foo2: String

        private attr_reader foo3: String

        # Attribute of bar
        attr_writer bar: Array[Integer]

        private attr_writer bar2: Array[Integer]

        attr_accessor baz: untyped

        private attr_accessor baz2: Integer
      end
    RBS
  end

  def test_public_private
    output = translate(<<~RUBY)
      class Hello
        public

        private()

        public :foo
      end
    RUBY

    assert_equal <<~RBS, output
      class Hello
        public

        private
      end
    RBS
  end

  def test_method__override
    output = translate(<<~RUBY)
      class Foo < String
        # @rbs override
        def length
        end
      end
    RUBY

    assert_equal <<~RBS, output
      class Foo < String
        # @rbs override
        def length: ...
      end
    RBS
  end

  def test_uses
    output = translate(<<~RUBY)
      # @rbs use String

      class Foo < String
        # @rbs override
        def length
        end
      end
    RUBY

    assert_equal <<~RBS, output
      use String

      class Foo < String
        # @rbs override
        def length: ...
      end
    RBS
  end

  def test_module_self
    output = translate(<<~RUBY)
      # @rbs module-self BasicObject, Integer
      module Foo

        def foo
        end
      end
    RUBY

    assert_equal <<~RBS, output
      # @rbs module-self BasicObject, Integer
      module Foo : BasicObject, Integer
        def foo: () -> untyped
      end
    RBS
  end

  def test_constant_decl
    output = translate(<<~RUBY)
      VERSION = "hogehoge"

      SIZE = [123] #: Array[Integer]

      NAMES = __dir__

      # @rbs skip
      SKIP = 123
    RUBY

    assert_equal <<~RBS, output
      VERSION: ::String

      SIZE: Array[Integer]

      NAMES: untyped
    RBS
  end

  def test_constant__without_decl
    output = translate(<<~RUBY)
      TAGS = []

      OPTIONS = {}
    RUBY

    assert_equal <<~RBS, output
      TAGS: ::Array[untyped]

      OPTIONS: ::Hash[untyped, untyped]
    RBS
  end

  def test_constant_decl_with_array_element_type_inference
    output = translate(<<~RUBY)
      STRINGS = ["a", "b", "c"]

      INTEGERS = [1, 2, 3]

      NESTED = [[1, 2], [3, 4]]

      WORDS_ONE = %w(foo bar baz)

      WORDS_TWO = %W(foo bar baz)

      WORDS_THREE = %w[foo bar baz]

      WORDS_FOUR = %W[foo bar baz]

      SYMBOLS_ONE = %i(foo bar baz)

      SYMBOLS_TWO = %I(foo bar baz)

      SYMBOLS_THREE = %i[foo bar baz]

      SYMBOLS_FOUR = %I[foo bar baz]
    RUBY

    assert_equal <<~RBS, output
      STRINGS: ::Array[::String]

      INTEGERS: ::Array[::Integer]

      NESTED: ::Array[::Array[::Integer]]

      WORDS_ONE: ::Array[::String]

      WORDS_TWO: ::Array[::String]

      WORDS_THREE: ::Array[::String]

      WORDS_FOUR: ::Array[::String]

      SYMBOLS_ONE: ::Array[::Symbol]

      SYMBOLS_TWO: ::Array[::Symbol]

      SYMBOLS_THREE: ::Array[::Symbol]

      SYMBOLS_FOUR: ::Array[::Symbol]
    RBS
  end

  def test_constant_decl_with_array_element_untyped_inference
    output = translate(<<~RUBY)
      EMPTY = []

      MIXED = [1, "two", :three]

      ARRAY_SPLAT = [*other]

      SPLAT_RANGE = [*(1..5)]

      SPLAT_ARRAY = [*[1, 2, 3]]

      ARRAY_WITH_VARS = [x, y, z]

      ARRAY_WITH_CONSTS = [FOO, BAR, BAZ]
    RUBY

    assert_equal <<~RBS, output
      EMPTY: ::Array[untyped]

      MIXED: ::Array[untyped]

      ARRAY_SPLAT: ::Array[untyped]

      SPLAT_RANGE: ::Array[untyped]

      SPLAT_ARRAY: ::Array[untyped]

      ARRAY_WITH_VARS: ::Array[untyped]

      ARRAY_WITH_CONSTS: ::Array[untyped]
    RBS
  end

  def test_constant_decl_with_unsupported_array_element_type_inference
    output = translate(<<~RUBY)
      ARRAY_NEW = Array.new

      ARRAY_NEW_SIZED = Array.new(3)

      ARRAY_NEW_BLOCK = Array.new(3) { |i| i }

      ARRAY_NEW_DEFAULT = Array.new(3, "Ruby")

      ARRAY_BRACKET = Array[1, 2, 3]

      RANGE_TO_A = (1..5).to_a

      RANGE_STR_TO_A = ("a".."e").to_a

      KERNEL_ARRAY_INT = Array(1)

      KERNEL_ARRAY_ARRAY = Array([1, 2, 3])

      KERNEL_ARRAY_RANGE = Array(1..5)
    RUBY

    assert_equal <<~RBS, output
      ARRAY_NEW: untyped

      ARRAY_NEW_SIZED: untyped

      ARRAY_NEW_BLOCK: untyped

      ARRAY_NEW_DEFAULT: untyped

      ARRAY_BRACKET: untyped

      RANGE_TO_A: untyped

      RANGE_STR_TO_A: untyped

      KERNEL_ARRAY_INT: untyped

      KERNEL_ARRAY_ARRAY: untyped

      KERNEL_ARRAY_RANGE: untyped
    RBS
  end

  def test_constant_decl_with_hash_element_type_inference
    output = translate(<<~RUBY)
      SYMBOL_KEY = { a: 1, b: 2 }

      STRING_KEY = { "a" => 1, "b" => 2 }

      NESTED = { a: { b: 1 }, c: { d: 2 } }
    RUBY

    assert_equal <<~RBS, output
      SYMBOL_KEY: ::Hash[::Symbol, ::Integer]

      STRING_KEY: ::Hash[::String, ::Integer]

      NESTED: ::Hash[::Symbol, ::Hash[::Symbol, ::Integer]]
    RBS
  end

  def test_constant_decl_with_hash_element_untyped_inference
    output = translate(<<~RUBY)
      EMPTY = {}

      MIXED = { a: 1, "b" => :two, 3 => "three" }

      HASH_SPLAT = {**other}

      HASH_WITH_VARS = { x => y }

      HASH_WITH_CONSTS = { FOO => BAR }
    RUBY

    assert_equal <<~RBS, output
      EMPTY: ::Hash[untyped, untyped]

      MIXED: ::Hash[untyped, untyped]

      HASH_SPLAT: ::Hash[untyped, untyped]

      HASH_WITH_VARS: ::Hash[untyped, untyped]

      HASH_WITH_CONSTS: ::Hash[untyped, untyped]
    RBS
  end
  
  def test_constant_decl_with_unsupported_hash_element_type_inference
    output = translate(<<~RUBY)
      HASH_NEW = Hash.new

      HASH_NEW_DEFAULT = Hash.new(0)

      HASH_BRACKET = Hash["a", 1, "b", 2]
    RUBY

    assert_equal <<~RBS, output
      HASH_NEW: untyped

      HASH_NEW_DEFAULT: untyped

      HASH_BRACKET: untyped
    RBS
  end

  def test_generic_class_module
    output = translate(<<~RUBY)
      # @rbs generic T
      module Foo
      end

      # @rbs generic X < Integer
      # @rbs generic out Y
      class Bar
      end
    RUBY

    assert_equal <<~RBS, output
      # @rbs generic T
      module Foo[T]
      end

      # @rbs generic X < Integer
      # @rbs generic out Y
      class Bar[X < Integer, out Y]
      end
    RBS
  end

  def test_ivar
    output = translate(<<~RUBY)
      module Foo
        # @rbs @foo: String -- This is something

        def foo #: void
        end

        # @rbs self.@foo: Integer -- Something another
      end
    RUBY

    assert_equal <<~RBS, output
      module Foo
        # This is something
        @foo: String

        def foo: () -> void

        # Something another
        self.@foo: Integer
      end
    RBS
  end


  def test_method_type__block_untyped
    output = translate(<<~RUBY)
      class Foo
        def foo(&)
        end

        def bar(&block)
        end
      end
    RUBY

    assert_equal <<~RBS, output
      class Foo
        def foo: () ?{ (?) -> untyped } -> untyped

        def bar: () ?{ (?) -> untyped } -> untyped
      end
    RBS
  end

  def test_method_type__block_yields_untyped
    output = translate(<<~RUBY)
      class Foo
        def foo(&)
        end
      end
    RUBY

    assert_equal <<~RBS, output
      class Foo
        def foo: () ?{ (?) -> untyped } -> untyped
      end
    RBS
  end

  def test_rbs_embedded
    output = translate(<<~RUBY)
      class Foo
        # @rbs!
        #   type t = String | Integer
        #
        # @rbs!
        #   interface _Hello
        #     def world: () -> void
        #   end
      end
    RUBY

    assert_equal <<~RBS, output
      class Foo
        type t = String | Integer

        interface _Hello
          def world: () -> void
        end
      end
    RBS
  end

  def test_include_nested_modules
    output = translate(<<~RUBY)
      module M
        module A
        end
      end

      class Foo
        include M::A
      end
    RUBY

    assert_equal <<~RBS, output
      module M
        module A
        end
      end

      class Foo
        include M::A
      end
    RBS
  end

  def test_include_dynamic_values
    output = translate(<<~RUBY)
      class A
        include Module.new
      end
    RUBY

    assert_equal <<~RBS, output
      class A
      end
    RBS
  end

  def test_singleton_class_definition
    output = translate(<<~RUBY)
      class X
        class << self
          def foo
          end
        end
      end

      module M
        class << self
          def bar
          end
        end
      end
    RUBY

    assert_equal <<~RBS, output
      class X
        def self.foo: () -> untyped
      end

      module M
        def self.bar: () -> untyped
      end
    RBS
  end

  def test_singleton_class_definition__visibility
    output = translate(<<~RUBY)
      class X
        class << self
          private

          def foo
          end

          def bar
          end

          public

          def buz
          end
        end
      end
    RUBY

    assert_equal <<~RBS, output
      class X
        private def self.foo: () -> untyped

        private def self.bar: () -> untyped

        def self.buz: () -> untyped
      end
    RBS
  end

  def test_method_type_rbs_dot3
    output = translate(<<~RUBY)
      class X
        # @rbs ...
        def foo
        end

        # @rbs () -> void | ...
        def bar
        end
      end
    RUBY

    assert_equal <<~RBS, output
      class X
        # @rbs ...
        def foo: ...

        # @rbs () -> void | ...
        def bar: () -> void
               | ...
      end
    RBS
  end

  def test_method_type_assertion_dot3
    output = translate(<<~RUBY)
      class X
        #: ...
        def foo
        end

        #: () -> void
        #: ...
        def bar
        end
      end
    RUBY

    assert_equal <<~RBS, output
      class X
        # : ...
        def foo: ...

        # : () -> void
        # : ...
        def bar: () -> void
               | ...
      end
    RBS
  end

  def test_block__no_module
    output = translate(<<~RUBY)
      module M
        class_methods do
          def foo #: Integer
            123
          end
        end
      end
    RUBY

    assert_equal <<~RBS, output
      module M
        def foo: () -> Integer
      end
    RBS
  end

  def test_block__module_decl
    output = translate(<<~RUBY)
      module M
        # @rbs module ClassMethods[A] : BasicObject
        class_methods do
          def foo #: Integer
            123
          end
        end
      end
    RUBY

    assert_equal <<~RBS, output
      module M
        # @rbs module ClassMethods[A] : BasicObject
        module ClassMethods[A] : BasicObject
          def foo: () -> Integer
        end
      end
    RBS
  end

  def test_block__class_decl
    output = translate(<<~RUBY)
      class Account
        # @rbs class ::ApplicationController
        controller do
          def foo #: Integer
            123
          end
        end
      end
    RUBY

    assert_equal <<~RBS, output
      class Account
        # @rbs class ::ApplicationController
        class ::ApplicationController
          def foo: () -> Integer
        end
      end
    RBS
  end

  def test_toplevel_definitions
    output = translate(<<~RUBY)
      NAME = "rbs_inline"

      def foo = 123

      alias bar foo

      # @rbs module ApplicationController
      controller do
        def foo
        end
      end

      class <<self
        def foo
        end
      end
    RUBY

    assert_equal <<~RBS, output
      NAME: ::String

      # @rbs module ApplicationController
      module ApplicationController
        def foo: () -> untyped
      end
    RBS
  end

  def test_toplevel_rbs!
    output = translate(<<~RUBY)
      # @rbs!
      #   type foo = String
      #   alias foo bar
    RUBY

    assert_equal <<~RBS, output
      type foo = String
    RBS
  end

  def test_only_toplevel_rbs!
    output = translate(<<~RUBY)
      # @rbs skip
      module Foo
        # @rbs! type bar = Symbol
      end
    RUBY

    assert_equal <<~RBS, output
    RBS
  end

  def test_module_block_annotations
    output = translate(<<~RUBY)
      # @rbs module ClassMethods
      class_methods do
        # @rbs @size: Integer
      end
    RUBY

    assert_equal <<~RBS, output
      # @rbs module ClassMethods
      module ClassMethods
        @size: Integer
      end
    RBS
  end

  def test_sclass_annotations
    output = translate(<<~RUBY)
      class String
        class <<self
          # @rbs! self.@name: String
        end
      end
    RUBY

    assert_equal <<~RBS, output
      class String
        self.@name: String
      end
    RBS
  end

  def test_data_assign_decl
    output = translate(<<~RUBY)
      # Account record
      #
      # @rbs %a{some-attributes-here}
      Account = Data.define(
        :id,    #: Integer
        :email, #: String
      )

      class Account
        Group = _ = Data.define(
          :name
        )
      end

      Measure = Data.define(
        :amount, #: Integer
        :unit #: Integer
      ) do
        UNITS = [:meter, :inch]

        def <=>(other) #: bool
          return unless other.is_a?(self.class) && other.unit == unit
          amount <=> other.amount
        end
        include Comparable
      end
    RUBY

    assert_equal <<~RBS, output
      # Account record
      #
      # @rbs %a{some-attributes-here}
      %a{some-attributes-here}
      class Account < Data
        attr_reader id(): Integer

        attr_reader email(): String

        def self.new: (Integer id, String email) -> instance
                    | (id: Integer, email: String) -> instance

        def self.members: () -> [ :id, :email ]

        def members: () -> [ :id, :email ]
      end

      class Account
        class Group < Data
          attr_reader name(): untyped

          def self.new: (untyped name) -> instance
                      | (name: untyped) -> instance

          def self.members: () -> [ :name ]

          def members: () -> [ :name ]
        end
      end

      class Measure < Data
        attr_reader amount(): Integer

        attr_reader unit(): Integer

        def self.new: (Integer amount, Integer unit) -> instance
                    | (amount: Integer, unit: Integer) -> instance

        def self.members: () -> [ :amount, :unit ]

        def members: () -> [ :amount, :unit ]

        def <=>: (untyped other) -> bool

        include Comparable
      end

      UNITS: ::Array[untyped]
    RBS
  end

  def test_struct_assign_decl
    output = translate(<<~RUBY)
      # Account record
      #
      Account = Struct.new(
        "Account",
        :id,    #: Integer
        :email, #: String
      )

      class Account
        Group = _ = Struct.new(
          :name,
          keyword_init: true
        )
      end

      Item = _ = Struct.new(
        :sku, #: String
        :price, #: Integer
        keyword_init: false
      )

      # @rbs %a{rbs-inline:new-args=required}
      # @rbs %a{rbs-inline:readonly-attributes=true}
      User = Struct.new(
        :name #: String
      )

      Measure = Struct.new(
        :amount, #: Integer
        :unit #: Integer
      ) do
        UNITS = [:meter, :inch]

        def <=>(other) #: bool
          return unless other.is_a?(self.class) && other.unit == unit
          amount <=> other.amount
        end

        include Comparable
      end
    RUBY

    assert_equal <<~RBS, output
      # Account record
      class Account < Struct[Integer | String]
        attr_accessor id(): Integer

        attr_accessor email(): String

        def self.new: (?Integer id, ?String email) -> instance
                    | (?id: Integer, ?email: String) -> instance
      end

      class Account
        class Group < Struct[untyped]
          attr_accessor name(): untyped

          def self.new: (?name: untyped) -> instance
                      | ({ ?name: untyped }) -> instance
        end
      end

      class Item < Struct[String | Integer]
        attr_accessor sku(): String

        attr_accessor price(): Integer

        def self.new: (?String sku, ?Integer price) -> instance
      end

      # @rbs %a{rbs-inline:new-args=required}
      # @rbs %a{rbs-inline:readonly-attributes=true}
      %a{rbs-inline:new-args=required}
      %a{rbs-inline:readonly-attributes=true}
      class User < Struct[String]
        attr_reader name(): String

        def self.new: (String name) -> instance
                    | (name: String) -> instance
      end

      class Measure < Struct[untyped]
        attr_accessor amount(): Integer

        attr_accessor unit(): Integer

        def self.new: (?Integer amount, ?Integer unit) -> instance
                    | (?amount: Integer, ?unit: Integer) -> instance

        def <=>: (untyped other) -> bool

        include Comparable
      end

      UNITS: ::Array[untyped]
    RBS
  end

  def test_method_type__untyped_customize
    output = translate(<<~RUBY) do
      class Foo
        def f
        end

        attr_reader :foo
      end
    RUBY
      _1.default_type = RBS::Parser::parse_type("__todo__")
    end

    assert_equal <<~RBS, output
      class Foo
        def f: () -> __todo__

        attr_reader foo: __todo__
      end
    RBS
  end

  def test_data_type__untyped_customize
    output = translate(<<~RUBY) do
      Foo = Data.define(
        :bar
      )
    RUBY
      _1.default_type = RBS::Parser::parse_type("__todo__")
    end

    assert_equal <<~RBS, output
      class Foo < Data
        attr_reader bar(): __todo__

        def self.new: (__todo__ bar) -> instance
                    | (bar: __todo__) -> instance

        def self.members: () -> [ :bar ]

        def members: () -> [ :bar ]
      end
    RBS
  end

  def test_struct_type__untyped_customize
    output = translate(<<~RUBY) do
      class Foo
        Bar = Struct.new(:foo, :bar)
        Baz = Struct.new(:foo, :bar, keyword_init: true)
        Qux = Struct.new(:foo, :bar, keyword_init: false)
        # @rbs %a{rbs-inline:readonly-attributes=true}
        Quux = Struct.new(:foo, :bar)
      end
    RUBY
      _1.default_type = RBS::Parser::parse_type("__todo__")
    end

    assert_equal <<~RBS, output
      class Foo
        class Bar < Struct[__todo__]
          attr_accessor foo(): __todo__

          attr_accessor bar(): __todo__

          def self.new: (?__todo__ foo, ?__todo__ bar) -> instance
                      | (?foo: __todo__, ?bar: __todo__) -> instance
        end

        class Baz < Struct[__todo__]
          attr_accessor foo(): __todo__

          attr_accessor bar(): __todo__

          def self.new: (?foo: __todo__, ?bar: __todo__) -> instance
                      | ({ ?foo: __todo__, ?bar: __todo__ }) -> instance
        end

        class Qux < Struct[__todo__]
          attr_accessor foo(): __todo__

          attr_accessor bar(): __todo__

          def self.new: (?__todo__ foo, ?__todo__ bar) -> instance
        end

        # @rbs %a{rbs-inline:readonly-attributes=true}
        %a{rbs-inline:readonly-attributes=true}
        class Quux < Struct[__todo__]
          attr_reader foo(): __todo__

          attr_reader bar(): __todo__

          def self.new: (?__todo__ foo, ?__todo__ bar) -> instance
                      | (?foo: __todo__, ?bar: __todo__) -> instance
        end
      end
    RBS
  end

  def test_constant_type__untyped_customize
    output = translate(<<~RUBY) do
      FOO = []
      BAR = {}
      BAZ = object
    RUBY
      _1.default_type = RBS::Parser::parse_type("__todo__")
    end

    assert_equal <<~RBS, output
      FOO: ::Array[__todo__]

      BAR: ::Hash[__todo__, __todo__]

      BAZ: __todo__
    RBS
  end
end
