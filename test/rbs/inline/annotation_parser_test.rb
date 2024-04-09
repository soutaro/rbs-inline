# frozen_string_literal: true

require "test_helper"

class RBS::Inline::AnnotationParserTest < Minitest::Test
  include RBS::Inline

  def parse_comments(src)
    Prism.parse_comments(src, filepath: "a.rb")
  end

  def test_result_group
    annots = AnnotationParser.parse(parse_comments(<<~RUBY))
      # test2
      #
      # @rbs size: Integer -- size of something
      # @rbs keyword: Symbol
      # @rbs block
      # @rbs x -- Hello world
      # @rbs y: Array[
      # @rbs z: Array[  -- something
      RUBY

    assert_equal 6, annots[0].annotations.size
    annots[0].annotations[0].tap do |annotation|
      assert_equal :size, annotation.name
      assert_equal "Integer", annotation.type.to_s
      assert_equal " size of something", annotation.comment
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
      assert_equal " Hello world", annotation.comment
    end
    annots[0].annotations[4].tap do |annotation|
      assert_equal :y, annotation.name
      assert_nil annotation.type
      assert_nil annotation.comment
    end
    annots[0].annotations[5].tap do |annotation|
      assert_equal :z, annotation.name
      assert_nil annotation.type
      assert_equal " something", annotation.comment
    end
  end
end
