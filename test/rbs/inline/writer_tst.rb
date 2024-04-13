# frozen_string_literal: true

require "test_helper"

class RBS::Inline::WriterTest < Minitest::Test
  include RBS::Inline

  def translate(src)
    uses, decls = Parser.parse(Prism.parse(src, filepath: "a.rb"))
    Writer.write(uses, decls)
  end

  def test_method_type
    output = translate(<<~RUBY)
      class Foo
        #:: () -> String
        #:: (String) -> Integer
        def foo(x = nil)
        end

        # @rbs x: Integer
        # @rbs y: Array[String]
        # @rbs foo: Symbol
        # @rbs bar: Integer?
        # @rbs rest: Hash[Symbol, String?]
        # @rbs return: void
        def f(x=0, *y, foo:, bar: nil, **rest)
        end

        def g(x=0, *y, foo:, bar: nil, **rest)
        end
      end
    RUBY

    assert_equal <<~RBS, output
      class Foo
        # :: () -> String
        # :: (String) -> Integer
        def foo: () -> String
               | (String) -> Integer

        # @rbs x: Integer
        # @rbs y: Array[String]
        # @rbs foo: Symbol
        # @rbs bar: Integer?
        # @rbs rest: Hash[Symbol, String?]
        # @rbs return: void
        def f: (?Integer x, *String y, foo: Symbol, ?bar: Integer?, **String? rest) -> void

        def g: (?untyped x, *untyped y, foo: untyped, ?bar: untyped, **untyped rest) -> untyped
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
end
