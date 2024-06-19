# frozen_string_literal: true

require "test_helper"

class RBS::Inline::AnnotationParser::TokenizerTest < Minitest::Test
  include RBS::Inline

  Tokenizer = AnnotationParser::Tokenizer

  def test_advance
    tree = AST::Tree.new(:test)

    tokenizer = Tokenizer.new(StringScanner.new("@rbs foo bar : [ ]"))
    tokenizer.advance(tree)
    tokenizer.advance(tree)

    assert_equal 0, tokenizer.current_position
    assert_equal [:kRBS, "@rbs"], tokenizer.lookahead1
    assert_equal [:tWHITESPACE, " "], tokenizer.lookahead2

    tokenizer.advance(tree)

    assert_equal 5, tokenizer.current_position
    assert_equal [:tLVAR, "foo"], tokenizer.lookahead1
    assert_equal [:tWHITESPACE, " "], tokenizer.lookahead2
  end

  def test_skip_to_comment__1
    tree = AST::Tree.new(:test)

    tokenizer = Tokenizer.new(StringScanner.new("@rbs -- Hello"))
    tokenizer.advance(tree)
    tokenizer.advance(tree)

    assert_equal "@rbs ", tokenizer.skip_to_comment

    assert_equal 5, tokenizer.current_position
    assert_equal [:kMINUS2, "--"], tokenizer.lookahead1
    assert_equal [:tWHITESPACE, " "], tokenizer.lookahead2
  end

  def test_skip_to_comment__2
    tree = AST::Tree.new(:test)

    tokenizer = Tokenizer.new(StringScanner.new("@rbs -- Hello"))
    tokenizer.advance(tree)
    tokenizer.advance(tree)

    tokenizer.advance(tree)

    assert_equal "", tokenizer.skip_to_comment

    assert_equal 5, tokenizer.current_position
    assert_equal [:kMINUS2, "--"], tokenizer.lookahead1
    assert_equal [:tWHITESPACE, " "], tokenizer.lookahead2
  end

  def test_skip_to_comment__3
    tree = AST::Tree.new(:test)

    tokenizer = Tokenizer.new(StringScanner.new("@rbs - Hello"))
    tokenizer.advance(tree)
    tokenizer.advance(tree)

    assert_equal "@rbs - Hello", tokenizer.skip_to_comment
  end

  def test_reset__1
    tree = AST::Tree.new(:test)

    tokenizer = Tokenizer.new(StringScanner.new("@rbs - Hello"))
    tokenizer.advance(tree)
    tokenizer.advance(tree)

    tokenizer.reset(10, tree)

    assert_equal 10, tokenizer.current_position
    assert_equal [:tLVAR, "lo"], tokenizer.lookahead1
    assert_equal [:kEOF, ""], tokenizer.lookahead2
  end

  def test_reset__2
    tree = AST::Tree.new(:test)

    tokenizer = Tokenizer.new(StringScanner.new("@rbs - Hello"))
    tokenizer.advance(tree)
    tokenizer.advance(tree)

    tokenizer.reset(2, tree)

    assert_equal 2, tokenizer.current_position
    assert_equal [:tLVAR, "bs"], tokenizer.lookahead1
    assert_equal [:tWHITESPACE, " "], tokenizer.lookahead2
  end

  def test_reset__3
    tree = AST::Tree.new(:test)

    tokenizer = Tokenizer.new(StringScanner.new("@rbs - Hello"))
    tokenizer.advance(tree)
    tokenizer.advance(tree)

    assert_raises do
      tokenizer.reset(30, tree)
    end
  end

  def test_reset__4__trivia_token_makes_current_position_different
    tree = AST::Tree.new(:test)

    tokenizer = Tokenizer.new(StringScanner.new("@rbs Hello"))
    tokenizer.advance(tree)
    tokenizer.advance(tree)

    tokenizer.reset(4, tree)

    assert_equal 5, tokenizer.current_position
  end
end
