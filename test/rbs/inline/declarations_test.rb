# frozen_string_literal: true

require "test_helper"

class RBS::Inline::AST::DeclarationsTest < Minitest::Test
  include RBS
  include RBS::Inline

  def parse_ruby(src)
    Prism.parse(src, filepath: "a.rb")
  end

  def test_class_decl
    result = parse_ruby(<<~RUBY)
      class Hello
      end
    RUBY

    decl = AST::Declarations::ClassDecl.new(result.value.statements.body[0], nil, nil)

    assert_equal TypeName.parse("Hello"), decl.class_name
  end

  def test_class_decl__super
    result = parse_ruby(<<~RUBY)
      class Hello < Object
      end
    RUBY

    decl = AST::Declarations::ClassDecl.new(result.value.statements.body[0], nil, nil)

    assert_equal TypeName.parse("Hello"), decl.class_name
  end
end
