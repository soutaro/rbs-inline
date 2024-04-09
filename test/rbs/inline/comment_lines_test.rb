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

    assert_equal "Sample code\n", lines.string
  end

  def test_string__multiline
    lines = AST::CommentLines.new(parse_comments(<<~RUBY))
      # Sample code:
      #   Hello World
      #
      # Another code:
    RUBY

    assert_equal <<~TEXT, lines.string
      Sample code:
        Hello World

      Another code:
    TEXT
  end
end
