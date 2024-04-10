# frozen_string_literal: true

require "test_helper"

class RBS::Inline::AST::CommentLinesTest < Minitest::Test
  include RBS::Inline

  def parse_comments(src)
    Prism.parse_comments(src, filepath: "a.rb")
  end

  def test_string__single_line
    lines = AST::CommentLines.new(parse_comments(<<~RUBY))
      # Sample code
    RUBY

    assert_equal "Sample code", lines.string
  end

  def test_string__multiline
    lines = AST::CommentLines.new(parse_comments(<<~RUBY))
      # Sample code:
      #   Hello World
      #
      # Another code:
    RUBY

    assert_equal <<~TEXT.chop, lines.string
      Sample code:
        Hello World

      Another code:
    TEXT
  end

  def test_comment_location
    comments = parse_comments(<<~RUBY)
      # Sample code:
      #   Hello World
    RUBY
    lines = AST::CommentLines.new(comments)

    assert_equal [comments[0], 2], lines.comment_location(0)
    assert_equal [comments[0], 14], lines.comment_location(12)
    assert_equal [comments[1], 2], lines.comment_location(13)
    assert_equal [comments[1], 15], lines.comment_location(26)
    assert_nil lines.comment_location(27)
  end
end
