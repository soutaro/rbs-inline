# frozen_string_literal: true

require "test_helper"

class RBS::Inline::ParserTest < Minitest::Test
  include RBS::Inline

  def parse_ruby(src)
    Prism.parse(src, filepath: "a.rb")
  end

  def test_class_decl
    Parser.parse(parse_ruby(<<~RUBY))
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
    assert_nil Parser.parse(parse_ruby(<<~RUBY))
      class Foo
      end
    RUBY
  end

  def test_continue_parsing__magic_comment
    refute_nil Parser.parse(parse_ruby(<<~RUBY))
      # rbs_inline: enabled

      class Foo
      end
    RUBY
  end

  def test_continue_parsing__annotation
    refute_nil Parser.parse(parse_ruby(<<~RUBY))
      class Foo
        attr_reader :foo #:: String
      end
    RUBY
  end
end
