# frozen_string_literal: true

require "test_helper"

class RBS::Inline::ParserTest < Minitest::Test
  include RBS::Inline

  def parse_ruby(src)
    Prism.parse(src, filepath: "a.rb")
  end

  def test_class_decl
    Parser.parse(parse_ruby(<<~RUBY), opt_in: false)
      class Foo
        # Hello world
        class Bar < Object
          def foo
          end
        end
      end
    RUBY
  end

  def test_stop_parsing
    assert_nil Parser.parse(parse_ruby(<<~RUBY), opt_in: false)
      # rbs_inline: disabled
      class Foo
      end
    RUBY

    assert_nil Parser.parse(parse_ruby(<<~RUBY), opt_in: true)
      class Foo
      end
    RUBY
  end

  def test_continue_parsing
    refute_nil Parser.parse(parse_ruby(<<~RUBY), opt_in: true)
      # rbs_inline: enabled

      class Foo
      end
    RUBY

    refute_nil Parser.parse(parse_ruby(<<~RUBY), opt_in: false)
      class Foo
      end
    RUBY
  end
end
