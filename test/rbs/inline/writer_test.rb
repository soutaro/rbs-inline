# frozen_string_literal: true

require "test_helper"

class RBS::Inline::WriterTest < Minitest::Test
  include RBS::Inline

  def translate(src, opt_in: true)
    src = "# rbs_inline: enabled\n\n" + src
    uses, decls = Parser.parse(Prism.parse(src, filepath: "a.rb"), opt_in: opt_in)
    Writer.write(uses, decls)
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
      end
    RUBY

    assert_equal <<~RBS, output
      class Foo
        alias eql? ==

        # foo is an alias of bar
        alias foo bar
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

        # Attribute of bar
        attr_writer :bar

        attr_accessor :baz
      end
    RUBY

    assert_equal <<~RBS, output
      class Hello
        attr_reader foo: untyped

        attr_reader foo2: untyped

        # Attribute of bar
        attr_writer bar: untyped

        attr_accessor baz: untyped
      end
    RBS
  end

  def test_attributes__typed
    output = translate(<<~RUBY)
      class Hello
        attr_reader :foo, :foo2, "hoge".to_sym #: String

        # Attribute of bar
        attr_writer :bar #: Array[Integer]

        attr_accessor :baz #: Integer |
      end
    RUBY

    assert_equal <<~RBS, output
      class Hello
        attr_reader foo: String

        attr_reader foo2: String

        # Attribute of bar
        attr_writer bar: Array[Integer]

        attr_accessor baz: untyped
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
      # @rbs module-self BasicObject
      module Foo

        def foo
        end
      end
    RUBY

    assert_equal <<~RBS, output
      # @rbs module-self BasicObject
      module Foo : BasicObject
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
end
