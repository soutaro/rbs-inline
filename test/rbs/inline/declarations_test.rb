# frozen_string_literal: true

require "test_helper"

class RBS::Inline::AST::DeclarationsTest < Minitest::Test
  include RBS::Inline

  def parse_ruby(src)
    Prism.parse(src, filepath: "a.rb")
  end

  def test_class_decl
    result = parse_ruby(<<~RUBY)
      class Hello
      end
    RUBY

    decl = AST::Declarations::ClassDecl.new(result.value.statements.body[0])

    assert_equal TypeName("Hello"), decl.class_name
  end
end
