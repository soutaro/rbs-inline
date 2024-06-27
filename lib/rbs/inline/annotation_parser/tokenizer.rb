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

        # Tokens that comes after the current position
        #
        # This is a four tuple of tokens.
        #
        # 1. The first array is a trivia tokens before current position
        # 2. The second token is the first lookahead token after the current position
        # 3. The third array is a trivia tokens between the first lookahead and the second lookahead
        # 4. The fourth token is the second lookahead token
        #
        attr_reader :lookahead_tokens #: [Array[token], token?, Array[token], token?]

        # Token that comes after the current position
        # @rbs %a{pure}
        def lookahead1 #: token?
          lookahead_tokens[1]
        end

        # Token that comes after `lookahead1`
        # @rbs %a{pure}
        def lookahead2 #: token?
          lookahead_tokens[3]
        end

        # Returns the current char position of the first lookahead token
        #
        # ```
        # __ foo ___ bar baz
        # ^^                 Trivia tokens before lookahead1
        #   ^                #current_position
        #    ^^^             lookahead1
        #        ^^^         Trivia tokens between lookahead1 and lookahead2
        #            ^^^     lookahead2
        #                ^    <= scanner.charpos
        # ```
        #
        def current_position #: Integer
          start = scanner.charpos
          start -= lookahead1[1].size if lookahead1
          lookahead_tokens[2].each {|_, s| start -= s.size }
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

          @lookahead_tokens = [[], nil, [], nil]
        end

        # Advances the scanner
        #
        # @rbs tree: AST::Tree -- Tree to insert trivia tokens
        # @rbs eat: bool -- true to add the current lookahead token into the tree
        # @rbs return: void
        def advance(tree, eat: false)
          consume_trivias(tree)
          last = lookahead_tokens[1]
          tree << last if eat

          lookahead_tokens[0].replace(lookahead_tokens[2])
          lookahead_tokens[1] = lookahead_tokens[3]
          lookahead_tokens[2].clear

          while s = scanner.scan(/\s+/)
            lookahead_tokens[2] << [:tWHITESPACE, s]
          end

          lookahead =
            case
            when scanner.eos?
              [:kEOF, ""]
            when s = scanner.scan(/@rbs!/)
              [:kRBSE, s]
            when s = scanner.scan(/@rbs\b/)
              [:kRBS, s]
            when s = scanner.scan(PUNCTS_RE)
              [PUNCTS.fetch(s), s]
            when s = scanner.scan(KW_RE)
              [KEYWORDS.fetch(s), s]
            when s = scanner.scan(/[A-Z]\w*/)
              [:tUIDENT, s]
            when s = scanner.scan(/_[A-Z]\w*/)
              [:tIFIDENT, s]
            when s = scanner.scan(/[a-z]\w*/)
              [:tLVAR, s]
            when s = scanner.scan(/![a-z]\w*/)
              [:tELVAR, s]
            when s = scanner.scan(/@\w+/)
              [:tATIDENT, s]
            when s = scanner.scan(/%a\{[^}]+\}/)
              [:tANNOTATION, s]
            when s = scanner.scan(/%a\[[^\]]+\]/)
              [:tANNOTATION, s]
            when s = scanner.scan(/%a\([^)]+\)/)
              [:tANNOTATION, s]
            end #: token?

          lookahead_tokens[3] = lookahead

          last
        end

        # @rbs (AST::Tree?) -> String
        def consume_trivias(tree)
          buf = +""

          lookahead_tokens[0].each do |tok|
            tree << tok if tree
            buf << tok[1]
          end
          lookahead_tokens[0].clear

          buf
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

          @lookahead_tokens = [[], nil, [], nil]

          advance(tree)
          advance(tree)
        end

        def rest #: String
          buf = +""
          lookahead_tokens[0].each {|_, s| buf << s }
          buf << lookahead1[1] if lookahead1
          lookahead_tokens[2].each {|_, s| buf << s }
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
          prefix = +""

          lookahead_tokens[0].each { prefix << _1[1] }
          lookahead_tokens[0].clear

          if type?(:kMINUS2)
            return prefix
          end

          prefix << lookahead1[1] if lookahead1
          lookahead_tokens[2].each { prefix << _1[1] }
          lookahead_tokens[2].clear

          if type2?(:kMINUS2)
            advance(_ = nil)  # The tree is unused because no trivia tokens are left
            return prefix
          end

          prefix << lookahead2[1] if lookahead2

          if string = scanner.scan_until(/--/)
            @lookahead_tokens = [[], nil, [], [:kMINUS2, "--"]]
            advance(_ = nil)  # The tree is unused because no trivia tokens are left
            prefix + string.delete_suffix("--")
          else
            s = scanner.rest
            @lookahead_tokens = [[], [:kEOF, ""], [], nil]
            scanner.terminate
            prefix + s
          end
        end
      end
    end
  end
end
