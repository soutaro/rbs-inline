# frozen_string_literal: true

require "test_helper"

class RBS::Inline::AST::Declarations::ConstantUtilTest < Minitest::Test
  include RBS::Inline

  def parse_ruby(src)
    Prism.parse(src, filepath: "a.rb").value.statements.child_nodes[0]
  end

  include RBS::Inline::AST::Declarations::ConstantUtil

  def test_read_constant_node
    assert_equal TypeName("Foo"), type_name(parse_ruby("Foo"))
  end

  def test_read_constant_path_node
    assert_equal TypeName("Foo::Bar"), type_name(parse_ruby("Foo::Bar"))
  end

  def test_read_constant_path_node_root
    assert_equal TypeName("::Foo::Bar"), type_name(parse_ruby("::Foo::Bar"))
  end
end
