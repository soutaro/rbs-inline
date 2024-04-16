# frozen_string_literal: true

require "test_helper"

class RBS::Inline::AnnotationParserTest < Minitest::Test
  include RBS::Inline

  def parse_comments(src)
    Prism.parse_comments(src, filepath: "a.rb")
  end

  def test_lvar_decl_annotation
    annots = AnnotationParser.parse(parse_comments(<<~RUBY))
      # @rbs size: Integer -- size of something
      # @rbs keyword: Symbol
      # @rbs block
      # @rbs x -- Hello world
      # @rbs y: Array[
      # @rbs z: Array[  --
      #   something
      #   More comments
      RUBY

    assert_equal 6, annots[0].annotations.size
    annots[0].annotations[0].tap do |annotation|
      assert_equal :size, annotation.name
      assert_equal "Integer", annotation.type.to_s
      assert_equal "-- size of something", annotation.comment
    end
    annots[0].annotations[1].tap do |annotation|
      assert_equal :keyword, annotation.name
      assert_equal "Symbol", annotation.type.to_s
      assert_nil annotation.comment
    end
    annots[0].annotations[2].tap do |annotation|
      assert_equal :block, annotation.name
      assert_nil annotation.type
      assert_nil annotation.comment
    end
    annots[0].annotations[3].tap do |annotation|
      assert_equal :x, annotation.name
      assert_nil annotation.type
      assert_equal "-- Hello world", annotation.comment
    end
    annots[0].annotations[4].tap do |annotation|
      assert_equal :y, annotation.name
      assert_nil annotation.type
      assert_nil annotation.comment
    end
    annots[0].annotations[5].tap do |annotation|
      assert_equal :z, annotation.name
      assert_nil annotation.type
      assert_equal "--\n  something\n  More comments", annotation.comment
    end
  end

  def test_return_type_annotation
    annots = AnnotationParser.parse(parse_comments(<<~RUBY))
      # @rbs return: Integer -- size of something
      # @rbs return: Symbol
      # @rbs return
      # @rbs return: Array[
      # @rbs return: Array[  -- something
      RUBY

    assert_equal 5, annots[0].annotations.size
    annots[0].annotations[0].tap do |annotation|
      assert_equal "Integer", annotation.type.to_s
      assert_equal "-- size of something", annotation.comment
    end
    annots[0].annotations[1].tap do |annotation|
      assert_equal "Symbol", annotation.type.to_s
      assert_nil annotation.comment
    end
    annots[0].annotations[2].tap do |annotation|
      assert_nil annotation.type
      assert_nil annotation.comment
    end
    annots[0].annotations[3].tap do |annotation|
      assert_nil annotation.type
      assert_nil annotation.comment
    end
    annots[0].annotations[4].tap do |annotation|
      assert_nil annotation.type
      assert_equal "-- something", annotation.comment
    end
  end

  def test_type_assertion
    annots = AnnotationParser.parse(parse_comments(<<~RUBY))
      #:: (String) -> void
      #:: [Integer, String]
      #:: [Integer
      #:: (
      #    String,
      #    Integer,
      #   ) -> void
      # :: String
      RUBY

    annots[0].annotations[0].tap do |annotation|
      assert_equal "(String) -> void", annotation.type.to_s
    end
    annots[0].annotations[1].tap do |annotation|
      assert_equal "[ Integer, String ]", annotation.type.to_s
    end
    annots[0].annotations[2].tap do |annotation|
      assert_nil annotation.type
    end
    annots[0].annotations[3].tap do |annotation|
      assert_equal "(String, Integer) -> void", annotation.type.to_s
    end
    annots[0].annotations[4].tap do |annotation|
      assert_nil annotation
    end
  end

  def test_type_application
    annots = AnnotationParser.parse(parse_comments(<<~RUBY))
      #[String, Integer]
      #[String[
      #[]
      # [String]
      RUBY

    annots[0].annotations[0].tap do |annotation|
      assert_equal ["String", "Integer"], annotation.types.map(&:to_s)
    end
    annots[0].annotations[1].tap do |annotation|
      assert_nil annotation.types
    end
    annots[0].annotations[2].tap do |annotation|
      assert_nil annotation.types
    end
    annots[0].annotations[3].tap do |annotation|
      assert_nil annotation
    end
  end

  def test_annotation
    annots = AnnotationParser.parse(parse_comments(<<~RUBY))
      # @rbs %a{pure} %a[hello] %a(world)
      RUBY

    annots[0].annotations[0].tap do |annotation|
      assert_equal ["%a{pure}", "%a[hello]", "%a(world)"], annotation.contents
    end
  end

  def test_skip
    annots = AnnotationParser.parse(parse_comments(<<~RUBY))
      # @rbs skip
      # @rbs skip: untyped
      RUBY

    annots[0].annotations[0].tap do |annotation|
      assert_instance_of AST::Annotations::Skip, annotation
    end
    annots[0].annotations[1].tap do |annotation|
      assert_instance_of AST::Annotations::VarType, annotation
    end
  end
end
