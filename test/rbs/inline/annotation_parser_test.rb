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
      # @rbs x: String
      # @rbs method: () -> void
      #            | (String) -> Integer
      # @rbs foo: Bar
    RUBY

    pp annots[0].annotations
  end
end
