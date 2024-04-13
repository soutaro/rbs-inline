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
end
