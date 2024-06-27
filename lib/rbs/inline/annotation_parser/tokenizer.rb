module RBS
  module Inline
    class AnnotationParser
      class Tokenizer
        KEYWORDS = {
          "return" => :kRETURN,
          "inherits" => :kINHERITS,
          "as" => :kAS,
          "override" => :kOVERRIDE,
          "use" => :kUSE,
          "module-self" => :kMODULESELF,
          "generic" => :kGENERIC,
          "in" => :kIN,
          "out" => :kOUT,
          "unchecked" => :kUNCHECKED,
          "self" => :kSELF,
          "skip" => :kSKIP,
          "yields" => :kYIELDS,
        } #: Hash[String, Symbol]
        KW_RE = /#{Regexp.union(KEYWORDS.keys)}\b/

        PUNCTS = {
          "::" => :kCOLON2,
          ":" => :kCOLON,
          "[" => :kLBRACKET,
          "]" => :kRBRACKET,
          "," => :kCOMMA,
          "**" => :kSTAR2,
          "*" => :kSTAR,
          "--" => :kMINUS2,
          "<" => :kLT,
          "..." => :kDOT3,
          "." => :kDOT,
          "->" => :kARROW,
          "{" => :kLBRACE,
          "(" => :kLPAREN,
          "&" => :kAMP,
          "?" => :kQUESTION,
          "|" => :kVBAR,
        } #: Hash[String, Symbol]
        PUNCTS_RE = Regexp.union(PUNCTS.keys) #: Regexp

        attr_reader :scanner #: StringScanner

        # Token that comes after the current position
        attr_reader :lookahead1 #: token?

        # Token that comes after `lookahead1`
        attr_reader :lookahead2 #: token?

        # Returns the current char position of the scanner
        #
        # ```
        # foo bar baz
        # ^^^             lookahead1
        #     ^^^         lookahead2
        #         ^    <= scanner.charpos
        # ```
        #
        def current_position #: Integer
          start = scanner.charpos
          start -= lookahead1[1].size if lookahead1
          start -= lookahead2[1].size if lookahead2
          start
        end

        def lookaheads #: Array[Symbol?]
          [lookahead1&.[](0), lookahead2&.[](0)]
        end

        # @rbs scanner: StringScanner
        # @rbs return: void
        def initialize(scanner)
          @scanner = scanner

          @lookahead1 = nil
          @lookahead2 = nil
        end

        # Advances the scanner
        #
        # @rbs tree: AST::Tree -- Tree to insert trivia tokens
        # @rbs eat: bool -- true to add the current lookahead token into the tree
        # @rbs return: void
        def advance(tree, eat: false)
          last = lookahead1
          @lookahead1 = lookahead2

          tree << last if eat

          case
          when scanner.eos?
            @lookahead2 = [:kEOF, ""]
          when s = scanner.scan(/\s+/)
            @lookahead2 = [:tWHITESPACE, s]
          when s = scanner.scan(/@rbs!/)
            @lookahead2 = [:kRBSE, s]
          when s = scanner.scan(/@rbs\b/)
            @lookahead2 = [:kRBS, s]
          when s = scanner.scan(PUNCTS_RE)
            @lookahead2 = [PUNCTS.fetch(s), s]
          when s = scanner.scan(KW_RE)
            @lookahead2 = [KEYWORDS.fetch(s), s]
          when s = scanner.scan(/[A-Z]\w*/)
            @lookahead2 = [:tUIDENT, s]
          when s = scanner.scan(/_[A-Z]\w*/)
            @lookahead2 = [:tIFIDENT, s]
          when s = scanner.scan(/[a-z]\w*/)
            @lookahead2 = [:tLVAR, s]
          when s = scanner.scan(/![a-z]\w*/)
            @lookahead2 = [:tELVAR, s]
          when s = scanner.scan(/@\w+/)
            @lookahead2 = [:tATIDENT, s]
          when s = scanner.scan(/%a\{[^}]+\}/)
            @lookahead2 = [:tANNOTATION, s]
          when s = scanner.scan(/%a\[[^\]]+\]/)
            @lookahead2 = [:tANNOTATION, s]
          when s = scanner.scan(/%a\([^)]+\)/)
            @lookahead2 = [:tANNOTATION, s]
          else
            @lookahead2 = nil
          end

          if lookahead1 && lookahead1[0] == :tWHITESPACE
            tree << lookahead1
            advance(tree)
          end
        end

        # Returns true if the scanner cannot consume next token
        def stuck? #: bool
          lookahead1.nil? && lookahead2.nil?
        end

        # Skips characters
        #
        # This method ensures the `current_position` will be the given `position`.
        #
        # @rbs position: Integer -- The new position
        # @rbs tree: AST::Tree -- Tree to insert trivia tokens
        # @rbs return: void
        def reset(position, tree)
          if scanner.charpos > position
            scanner.reset()
          end

          skips = position - scanner.charpos

          if scanner.rest_size < skips
            raise "The position is bigger than the size of the rest of the input: input size=#{scanner.string.size}, position=#{position}"
          end

          scanner.skip(/.{#{skips}}/)

          @lookahead1 = nil
          @lookahead2 = nil

          advance(tree)
          advance(tree)
        end

        def rest #: String
          buf = +""
          buf << lookahead1[1] if lookahead1
          buf << lookahead2[1] if lookahead2
          buf << scanner.rest
          buf
        end

        # Consume given token type and inserts the token to the tree or `nil`
        #
        # @rbs *types: Symbol
        # @rbs tree: AST::Tree
        # @rbs return: void
        def consume_token(*types, tree:)
          if type?(*types)
            advance(tree, eat: true)
          else
            tree << nil
          end
        end

        # Consume given token type and inserts the token to the tree or raise
        #
        # @rbs *types: Symbol
        # @rbs tree: AST::Tree
        # @rbs return: void
        def consume_token!(*types, tree:)
          type!(*types)
          advance(tree, eat: true)
        end

        # Test if current token has specified `type`
        #
        # @rbs *types: Symbol
        # @rbs return: bool
        def type?(*types)
          types.any? { lookahead1 && lookahead1[0] == _1 }
        end

        # Test if lookahead2 token have specified `type`
        #
        # @rbs *types: Symbol -- The type of the lookahead2 token
        # @rbs return: bool
        def type2?(*types)
          types.any? { lookahead2 && lookahead2[0] == _1 }
        end

        # Ensure current token is one of the specified in types
        #
        # @rbs *types: Symbol
        # @rbs return: void
        def type!(*types)
          raise "Unexpected token: #{lookahead1&.[](0)}, where expected token: #{types.join(",")}" unless type?(*types)
        end

        # Reset the current_token to incoming comment `--`
        #
        # Reset to the end of the input if `--` token cannot be found.
        #
        # @rbs return: String -- String that is skipped
        def skip_to_comment
          return "" if type?(:kMINUS2)

          prefix = +""
          prefix << lookahead1[1] if lookahead1
          prefix << lookahead2[1] if lookahead2

          if string = scanner.scan_until(/--/)
            @lookahead1 = nil
            @lookahead2 = [:kMINUS2, "--"]
            advance(_ = nil)  # The tree is unused because lookahead2 is not a trivia token
            prefix + string.delete_suffix("--")
          else
            s = scanner.rest
            @lookahead1 = [:kEOF, ""]
            @lookahead2 = nil
            scanner.terminate
            prefix + s
          end
        end
      end
    end
  end
end
