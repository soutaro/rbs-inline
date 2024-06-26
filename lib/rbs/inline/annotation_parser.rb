# rbs_inline: enabled

module RBS
  module Inline
    class AnnotationParser
      # ParsingResut groups consecutive comments, which may contain several annotations
      #
      # *Consecutive comments* are comments are defined in below.
      # They are basically comments that follows from the previous line, but there are some more requirements.
      #
      # ```ruby
      # # Line 1
      # # Line 2           #=> Line 1 and Line 2 are consecutive
      #
      #    # Line 3
      #  # Line4           #=> Line 3 and Line 4 are not consecutive, because the starting column are different
      #
      #         # Line 5
      # foo()   # Line 6   #=> Line 5 and Line 6 are not consecutive, because Line 6 has leading code
      # ```
      #
      class ParsingResult
        attr_reader :comments #: Array[Prism::Comment]
        attr_reader :annotations #: Array[AST::Annotations::t | AST::CommentLines]
        attr_reader :first_comment_offset #: Integer

        #: () { (AST::Annotations::t) -> void } -> void
        #: () -> Enumerator[AST::Annotations::t, void]
        def each_annotation(&block)
          if block
            annotations.each do |annot|
              if annot.is_a?(AST::Annotations::Base)
                yield annot
              end
            end
          else
            enum_for :each_annotation
          end
        end

        # @rbs first_comment: Prism::Comment
        def initialize(first_comment) #: void
          @comments = [first_comment]
          @annotations = []
          content = first_comment.location.slice
          index = content.index(/[^#\s]/) || content.size
          @first_comment_offset = index
        end

        # @rbs return: Range[Integer]
        def line_range
          first = comments.first or raise
          last = comments.last or raise

          first.location.start_line .. last.location.end_line
        end

        # @rbs return: Prism::Comment
        def last_comment
          comments.last or raise
        end

        # @rbs comment: Prism::Comment
        # @rbs return: self?
        def add_comment(comment)
          if last_comment.location.end_line + 1 == comment.location.start_line
            if last_comment.location.start_column == comment.location.start_column
              if prefix = comment.location.start_line_slice[..comment.location.start_column]
                prefix.strip!
                if prefix.empty?
                  comments << comment
                  self
                end
              end
            end
          end
        end

        # @rbs trim: bool -- `true` to trim the leading whitespaces
        def content(trim: false) #: String
          if trim
            leading_spaces = lines[0][/\A\s*/]
            offset = leading_spaces ? leading_spaces.length : 0

            lines.map do |line|
              prefix = line[0..offset] || ""
              if prefix.strip.empty?
                line[offset..]
              else
                line.lstrip
              end
            end.join("\n")
          else
            lines.join("\n")
          end
        end

        def lines #: Array[String]
          comments.map { _1.location.slice[1...] || "" }
        end
      end

      attr_reader :input #: Array[Prism::Comment]

      # @rbs input: Array[Prism::Comment]
      def initialize(input) #: void
        @input = input
      end

      # @rbs input: Array[Prism::Comment]
      # @rbs return: Array[ParsingResult]
      def self.parse(input)
        new(input).parse
      end

      # @rbs return: Array[ParsingResult]
      def parse
        results = [] #: Array[ParsingResult]

        first_comment, *rest = input
        first_comment or return results

        result = ParsingResult.new(first_comment)
        results << result

        rest.each do |comment|
          unless result.add_comment(comment)
            result = ParsingResult.new(comment)
            results << result
          end
        end

        results.each do |result|
          each_annotation_paragraph(result) do |comments, annotation|
            lines = AST::CommentLines.new(comments)

            if annotation && annot = parse_annotation(lines)
              result.annotations << annot
            else
              result.annotations << lines
            end
          end
        end

        results
      end

      private

      # Test if the comment is an annotation comment
      #
      # - Returns `nil` if the comment is not an annotation.
      # - Returns `true` if the comment is `#:` or `#[` annotation. (Offset is `1`)
      # - Returns Integer if the comment is `#@rbs` annotation. (Offset is the number of leading spaces including `#`)
      #
      #: (Prism::Comment) -> (Integer | true | nil)
      def annotation_comment?(comment)
        line = comment.location.slice

        # No leading whitespace is allowed
        return true if line.start_with?("#:")
        return true if line.start_with?("#[")

        if match = line.match(/\A#(\s*)@rbs(\b|!)/)
          leading_spaces = match[1] or raise
          leading_spaces.size + 1
        end
      end

      # Split lines of comments in `result` into paragraphs
      #
      # A paragraph consists of:
      #
      # * An annotation syntax constructs -- starting with `@rbs` or `::`, or
      # * A lines something else
      #
      # Yields an array of comments, and a boolean indicating if the comments may be an annotation.
      #
      #: (ParsingResult) { (Array[Prism::Comment], bool is_annotation) -> void } -> void
      def each_annotation_paragraph(result, &block)
        yield_paragraph([], result.comments.dup, &block)
      end

      # The first annotation line is already detected and consumed.
      # The annotation comment is already in `comments`.
      #
      # @rbs comments: Array[Prism::Comment] -- Annotation comments
      # @rbs lines: Array[Prism::Comment] -- Lines to be consumed
      # @rbs offset: Integer -- Offset of the first character of the first annotation comment from the `#` (>= 1)
      # @rbs allow_empty_lines: bool -- `true` if empty line is allowed inside the annotation comments
      # @rbs &block: (Array[Prism::Comment], bool is_annotation) -> void
      # @rbs return: void
      def yield_annotation(comments, lines, offset, allow_empty_lines:, &block)
        first_comment = lines.first

        if first_comment
          nonspace_index = first_comment.location.slice.index(/\S/, 1)

          case
          when nonspace_index.nil?
            if allow_empty_lines
              lines.shift
              yield_empty_annotation(comments, [first_comment], lines, offset, &block)
            else
              # Starting next paragraph (or annotation)
              yield(comments, true)
              yield_paragraph([], lines, &block)
            end
          when nonspace_index > offset
            # Continuation of the annotation
            lines.shift
            comments.push(first_comment)
            yield_annotation(comments, lines, offset, allow_empty_lines: allow_empty_lines, &block)
          else
            # Starting next paragraph (or annotation)
            yield(comments, true)
            yield_paragraph([], lines, &block)
          end
        else
          yield(comments, true)
        end
      end

      # The first line is NOT consumed.
      #
      # The `comments` may be empty.
      #
      # @rbs comments: Array[Prism::Comment] -- Leading comments
      # @rbs lines: Array[Prism::Comment] -- Lines to be consumed
      # @rbs &block: (Array[Prism::Comment], bool is_annotation) -> void
      # @rbs return: void
      def yield_paragraph(comments, lines, &block)
        while first_comment = lines.first
          if offset = annotation_comment?(first_comment)
            yield comments, false unless comments.empty?
            lines.shift
            case offset
            when Integer
              yield_annotation([first_comment], lines, offset, allow_empty_lines: true, &block)
            when true
              yield_annotation([first_comment], lines, 1, allow_empty_lines: false, &block)
            end
            return
          else
            lines.shift
            comments.push(first_comment)
          end
        end

        yield comments, false unless comments.empty?
      end

      # Consumes empty lines between annotation lines
      #
      # An empty line is already detected and consumed.
      # The line is already removed from `lines` and put in `empty_comments`.
      #
      # Note that the arguments, `comments`, `empty_comments`, and `lines` are modified in place.
      #
      # @rbs comments: Array[Prism::Comment] -- Non empty annotation comments
      # @rbs empty_comments: Array[Prism::Comment] -- Empty comments that may be part of the annotation
      # @rbs lines: Array[Prism::Comment] -- Lines
      # @rbs offset: Integer -- Offset of the first character of the annotation
      # @rbs &block: (Array[Prism::Comment], bool is_annotation) -> void
      # @rbs return: void
      def yield_empty_annotation(comments, empty_comments, lines, offset, &block)
        first_comment = lines.first

        if first_comment
          nonspace_index = first_comment.location.slice.index(/\S/, 1)

          case
          when nonspace_index.nil?
            # Empty line, possibly continues the annotation
            lines.shift
            empty_comments << first_comment
            yield_empty_annotation(comments, empty_comments, lines, offset, &block)
          when nonspace_index > offset
            # Continuation of the annotation
            lines.shift
            comments.concat(empty_comments)
            comments.push(first_comment)
            yield_annotation(comments, lines, offset, allow_empty_lines: true, &block)
          else
            yield comments, true
            yield_paragraph(empty_comments, lines, &block)
          end
        else
          # EOF
          yield comments, true
          yield empty_comments, false
        end
      end

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

      # @rbs comments: AST::CommentLines
      # @rbs return: AST::Annotations::t?
      def parse_annotation(comments)
        scanner = StringScanner.new(comments.string)
        tokenizer = Tokenizer.new(scanner)

        tree = AST::Tree.new(:rbs_annotation)
        tokenizer.advance(tree)
        tokenizer.advance(tree)

        case
        when tokenizer.type?(:kRBSE)
          tree << tokenizer.lookahead1
          rest = tokenizer.rest
          rest.delete_prefix!("@rbs!")
          tree << [:EMBEDDED_RBS, rest]
          tokenizer.scanner.terminate
          AST::Annotations::Embedded.new(tree, comments)
        when tokenizer.type?(:kRBS)
          tokenizer.advance(tree, eat: true)

          case
          when tokenizer.type?(:tLVAR, :tELVAR)
            tree << parse_var_decl(tokenizer)
            AST::Annotations::VarType.new(tree, comments)
          when tokenizer.type?(:kSKIP, :kINHERITS, :kOVERRIDE, :kUSE, :kGENERIC) &&
            tokenizer.type2?(:kCOLON)
            tree << parse_var_decl(tokenizer)
            AST::Annotations::VarType.new(tree, comments)
          when tokenizer.type?(:kSKIP)
            AST::Annotations::Skip.new(tree, comments)
          when tokenizer.type?(:kRETURN)
            tree << parse_return_type_decl(tokenizer)
            AST::Annotations::ReturnType.new(tree, comments)
          when tokenizer.type?(:tANNOTATION)
            tree << parse_rbs_annotation(tokenizer)
            AST::Annotations::RBSAnnotation.new(tree, comments)
          when tokenizer.type?(:kINHERITS)
            tree << parse_inherits(tokenizer)
            AST::Annotations::Inherits.new(tree, comments)
          when tokenizer.type?(:kOVERRIDE)
            tree << parse_override(tokenizer)
            AST::Annotations::Override.new(tree, comments)
          when tokenizer.type?(:kUSE)
            tree << parse_use(tokenizer)
            AST::Annotations::Use.new(tree, comments)
          when tokenizer.type?(:kMODULESELF)
            tree << parse_module_self(tokenizer)
            AST::Annotations::ModuleSelf.new(tree, comments)
          when tokenizer.type?(:kGENERIC)
            tree << parse_generic(tokenizer)
            AST::Annotations::Generic.new(tree, comments)
          when tokenizer.type?(:kSELF, :tATIDENT)
            tree << parse_ivar_type(tokenizer)
            AST::Annotations::IvarType.new(tree, comments)
          when tokenizer.type?(:kSTAR)
            tree << parse_splat_param_type(tokenizer)
            AST::Annotations::SplatParamType.new(tree, comments)
          when tokenizer.type?(:kSTAR2)
            tree << parse_splat_param_type(tokenizer)
            AST::Annotations::DoubleSplatParamType.new(tree, comments)
          when tokenizer.type?(:kAMP)
            tree << parse_block_type(tokenizer)
            AST::Annotations::BlockType.new(tree, comments)
          when tokenizer.type?(:kLPAREN, :kARROW, :kLBRACE, :kLBRACKET, :kDOT3)
            tree << parse_method_type_annotation(tokenizer)
            AST::Annotations::Method.new(tree, comments)
          end
        when tokenizer.type?(:kCOLON)
          tokenizer.advance(tree, eat: true)

          if tokenizer.type?(:kDOT3)
            tokenizer.advance(tree, eat: true)
            AST::Annotations::Dot3Assertion.new(tree, comments)
          else
            type = parse_type_method_type(tokenizer, tree)
            tree << type

            case type
            when MethodType
              AST::Annotations::MethodTypeAssertion.new(tree, comments)
            when AST::Tree, nil
              AST::Annotations::SyntaxErrorAssertion.new(tree, comments)
            else
              AST::Annotations::TypeAssertion.new(tree, comments)
            end
          end
        when tokenizer.type?(:kLBRACKET)
          tree << parse_type_app(tokenizer)
          AST::Annotations::Application.new(tree, comments)
        end
      end

      # @rbs tokenizer: Tokenizer
      # @rbs return: AST::Tree
      def parse_var_decl(tokenizer)
        tree = AST::Tree.new(:var_decl)

        tokenizer.advance(tree, eat: true)

        if tokenizer.type?(:kCOLON)
          tree << tokenizer.lookahead1
          tokenizer.advance(tree)
        else
          tree << nil
        end

        tree << parse_type(tokenizer, tree)

        if tokenizer.type?(:kMINUS2)
          tree << parse_comment(tokenizer)
        else
          tree << nil
        end

        tree
      end

      # @rbs tokenizer: Tokenizer
      # @rbs return: AST::Tree
      def parse_return_type_decl(tokenizer)
        tree = AST::Tree.new(:return_type_decl)

        tokenizer.consume_token!(:kRETURN, tree: tree)
        tokenizer.consume_token(:kCOLON, tree: tree)
        tree << parse_type(tokenizer, tree)
        tree << parse_optional(tokenizer, :kMINUS2) { parse_comment(tokenizer) }

        tree
      end

      # @rbs tokenizer: Tokenizer
      # @rbs return: AST::Tree
      def parse_comment(tokenizer)
        tree = AST::Tree.new(:comment)

        tokenizer.consume_token(:kMINUS2, tree: tree)

        rest = tokenizer.rest
        tokenizer.scanner.terminate
        tree << [:tCOMMENT, rest]

        tree
      end

      # @rbs tokenizer: Tokenizer
      # @rbs return: AST::Tree
      def parse_type_app(tokenizer)
        tree = AST::Tree.new(:tapp)

        if tokenizer.type?(:kLBRACKET)
          tree << tokenizer.lookahead1
          tokenizer.advance(tree)
        end

        types = AST::Tree.new(:types)
        while true
          type = parse_type(tokenizer, types)
          types << type

          break unless type
          break if type.is_a?(AST::Tree)

          if tokenizer.type?(:kCOMMA)
            types << tokenizer.lookahead1
            tokenizer.advance(types)
          end

          if tokenizer.type?(:kRBRACKET)
            break
          end
        end
        tree << types

        if tokenizer.type?(:kRBRACKET)
          tree << tokenizer.lookahead1
          tokenizer.advance(tree)
        end

        tree
      end

      # @rbs (Tokenizer) -> AST::Tree
      def parse_method_type_annotation(tokenizer)
        tree = AST::Tree.new(:method_type_annotation)

        until tokenizer.type?(:kEOF)
          if tokenizer.type?(:kDOT3)
            tree << tokenizer.lookahead1
            tokenizer.advance(tree)
            break
          else
            method_type = parse_method_type(tokenizer, tree)
            case method_type
            when MethodType
              tree << method_type

              if tokenizer.type?(:kVBAR)
                tokenizer.advance(tree, eat: true)
              else
                break
              end
            when AST::Tree
              tree << method_type
              break
            end
          end
        end

        tree
      end

      # Parse a RBS method type or type and returns it
      #
      # It tries parsing a method type, and then parsing a type if failed.
      #
      # If both parsing failed, it returns a Tree(`:type_syntax_error), consuming all of the remaining input.
      #
      # Note that this doesn't recognize `--` comment unlike `parse_type`.
      #
      # @rbs tokenizer: Tokenizer
      # @rbs parent_tree: AST::Tree
      # @rbs return: MethodType | AST::Tree | Types::t | nil
      def parse_type_method_type(tokenizer, parent_tree)
        buffer = RBS::Buffer.new(name: "", content: tokenizer.scanner.string)
        range = (tokenizer.current_position..)
        begin
          if type = RBS::Parser.parse_method_type(buffer, range: range, require_eof: false)
            loc = type.location or raise
            tokenizer.reset(loc.end_pos, parent_tree)
            type
          else
            nil
          end
        rescue RBS::ParsingError
          begin
            if type = RBS::Parser.parse_type(buffer, range: range, require_eof: false)
              loc = type.location or raise
              tokenizer.reset(loc.end_pos, parent_tree)
              type
            else
              nil
            end
          rescue RBS::ParsingError
            tree = AST::Tree.new(:type_syntax_error)
            tree << [:tSOURCE, tokenizer.rest]
            tokenizer.scanner.terminate
            tree
          end
        end
      end

      # Parse a RBS method type
      #
      # If parsing failed, it returns a Tree(`:type_syntax_error), consuming all of the remaining input.
      #
      # Note that this doesn't recognize `--` comment unlike `parse_type`.
      #
      # @rbs tokenizer: Tokenizer
      # @rbs parent_tree: AST::Tree
      # @rbs return: MethodType | AST::Tree
      def parse_method_type(tokenizer, parent_tree)
        buffer = RBS::Buffer.new(name: "", content: tokenizer.scanner.string)
        range = (tokenizer.current_position..)
        begin
          if type = RBS::Parser.parse_method_type(buffer, range: range, require_eof: false)
            loc = type.location or raise
            tokenizer.reset(loc.end_pos, parent_tree)
            type
          else
            tree = AST::Tree.new(:type_syntax_error)
            tree << [:tSOURCE, tokenizer.rest]
            tokenizer.scanner.terminate
            tree
          end
        rescue RBS::ParsingError
          tree = AST::Tree.new(:type_syntax_error)
          tree << [:tSOURCE, tokenizer.rest]
          tokenizer.scanner.terminate
          tree
        end
      end

      # Parse a RBS type and returns it
      #
      # If parsing failed, it returns a Tree(`:type_syntax_error), consuming
      #
      # 1. All of the input with `--` token if exists (for comments)
      # 2. All of the input (for anything else)
      #
      # ```
      # Integer -- Foo        # => Returns `Integer`, tokenizer has `--` as its current token
      # Integer[ -- Foo       # => Returns a tree for `Integer[`, tokenizer has `--` as its current token
      # Integer[ Foo          # => Returns a tree for `Integer[ Foo`, tokenizer is at the end of the input
      # ```
      #
      # @rbs tokenizer: Tokenizer
      # @rbs parent_tree: AST::Tree
      # @rbs return: Types::t | AST::Tree | nil
      def parse_type(tokenizer, parent_tree)
        buffer = RBS::Buffer.new(name: "", content: tokenizer.scanner.string)
        range = (tokenizer.current_position..)
        if type = RBS::Parser.parse_type(buffer, range: range, require_eof: false)
          loc = type.location or raise
          tokenizer.reset(loc.end_pos, parent_tree)
          type
        else
          nil
        end
      rescue RBS::ParsingError
        content = tokenizer.skip_to_comment
        tree = AST::Tree.new(:type_syntax_error)
        tree << [:tSOURCE, content]
        tree
      end

      # @rbs tokenizer: Tokenizer
      # @rbs return: AST::Tree
      def parse_rbs_annotation(tokenizer)
        tree = AST::Tree.new(:rbs_annotation)

        while tokenizer.type?(:tANNOTATION)
          tree << tokenizer.lookahead1
          tokenizer.advance(tree)
        end

        tree
      end

      # @rbs tokenizer: Tokenizer
      # @rbs return: AST::Tree
      def parse_inherits(tokenizer)
        tree = AST::Tree.new(:rbs_inherits)

        if tokenizer.type?(:kINHERITS)
          tree << tokenizer.lookahead1
          tokenizer.advance(tree)
        end

        tree << parse_type(tokenizer, tree)

        tree
      end

      # Parse `@rbs override` annotation
      #
      # @rbs tokenizer: Tokenizer
      # @rbs return: AST::Tree
      def parse_override(tokenizer)
        tree = AST::Tree.new(:override)

        if tokenizer.type?(:kOVERRIDE)
          tree << tokenizer.lookahead1
          tokenizer.advance(tree)
        end

        tree
      end

      # Parse `@rbs use [CLAUSES]` annotation
      #
      # @rbs tokenizer: Tokenizer
      # @rbs return: AST::Tree
      def parse_use(tokenizer)
        tree = AST::Tree.new(:use)

        if tokenizer.type?(:kUSE)
          tree << tokenizer.lookahead1
          tokenizer.advance(tree)
        end

        while tokenizer.type?(:kCOLON2, :tUIDENT, :tIFIDENT, :tLVAR)
          tree << parse_use_clause(tokenizer)

          if tokenizer.type?(:kCOMMA)
            tokenizer.advance(tree, eat: true)
          else
            tree << nil
          end
        end

        tree
      end

      # Parses use clause
      #
      # Returns one of the following form:
      #
      # * [`::`?, [UIDENT, `::`]*, LIDENT, [`as` LIDENT]?]
      # * [`::`?, [UIDENT, `::`]*, UIDENT, [`as` UIDENT]?]
      # * [`::`?, [UIDENT, `::`]*, IFIDENT, [`as`, IFIDENT]?]
      # * [`::`?, [UIDENT) `::`]*, `*`]
      #
      # @rbs tokenizer: Tokenizer
      # @rbs return: AST::Tree
      def parse_use_clause(tokenizer)
        tree = AST::Tree.new(:use_clause)

        if tokenizer.type?(:kCOLON2)
          tree << tokenizer.lookahead1
          tokenizer.advance(tree)
        end

        while true
          case
          when tokenizer.type?(:tUIDENT)
            tokenizer.advance(tree, eat: true)

            case
            when tokenizer.type?(:kCOLON2)
              tokenizer.advance(tree, eat: true)
            else
              break
            end
          else
            break
          end
        end

        case
        when tokenizer.type?(:tLVAR)
          tokenizer.advance(tree, eat: true)
        when tokenizer.type?(:tIFIDENT)
          tokenizer.advance(tree, eat: true)
        when tokenizer.type?(:kSTAR)
          tokenizer.advance(tree, eat: true)
          return tree
        end

        if tokenizer.type?(:kAS)
          as_tree = AST::Tree.new(:as)

          tokenizer.consume_token!(:kAS, tree: as_tree)
          tokenizer.consume_token(:tLVAR, :tIFIDENT, :tUIDENT, tree: as_tree)

          tree << as_tree
        else
          tree << nil
        end

        tree
      end

      # @rbs tokenizer: Tokenizer
      # @rbs return: AST::Tree
      def parse_module_self(tokenizer)
        tree = AST::Tree.new(:module_self)

        tokenizer.consume_token!(:kMODULESELF, tree: tree)
        tree << parse_type(tokenizer, tree)

        if tokenizer.type?(:kMINUS2)
          tree << parse_comment(tokenizer)
        else
          tree << nil
        end

        tree
      end

      # Yield the block and return the resulting tree if tokenizer has current token of `types`
      #
      # ```rb
      # # Test if tokenize has `--` token, then parse comment or insert `nil` to tree
      #
      # tree << parse_optional(tokenizer, :kMINUS2) do
      #   parse_comment(tokenizer)
      # end
      # ```
      #
      # @rbs tokenizer: Tokenizer
      # @rbs *types: Symbol
      # @rbs &block: () -> AST::Tree
      # @rbs return: AST::Tree?
      def parse_optional(tokenizer, *types, &block)
        if tokenizer.type?(*types)
          yield
        end
      end

      # @rbs tokenizer: Tokenizer
      # @rbs return: AST::Tree
      def parse_generic(tokenizer)
        tree = AST::Tree.new(:generic)

        tokenizer.consume_token!(:kGENERIC, tree: tree)

        tokenizer.consume_token(:kUNCHECKED, tree: tree)
        tokenizer.consume_token(:kIN, :kOUT, tree: tree)

        tokenizer.consume_token(:tUIDENT, tree: tree)

        tree << parse_optional(tokenizer, :kLT) do
          bound = AST::Tree.new(:upper_bound)

          tokenizer.consume_token!(:kLT, tree: bound)
          bound << parse_type(tokenizer, bound)

          bound
        end

        tree << parse_optional(tokenizer, :kMINUS2) do
          parse_comment(tokenizer)
        end

        tree
      end

      #: (Tokenizer) -> AST::Tree
      def parse_ivar_type(tokenizer)
        tree = AST::Tree.new(:ivar_type)

        tokenizer.consume_token(:kSELF, tree: tree)
        tokenizer.consume_token(:kDOT, tree: tree)

        tokenizer.consume_token(:tATIDENT, tree: tree)
        tokenizer.consume_token(:kCOLON, tree: tree)

        tree << parse_type(tokenizer, tree)

        tree << parse_optional(tokenizer, :kMINUS2) do
          parse_comment(tokenizer)
        end

        tree
      end

      #: (Tokenizer) -> AST::Tree
      def parse_splat_param_type(tokenizer)
        tree = AST::Tree.new(:splat_param_type)

        tokenizer.consume_token!(:kSTAR, :kSTAR2, tree: tree)
        tokenizer.consume_token(:tLVAR, tree: tree)
        tokenizer.consume_token(:kCOLON, tree: tree)

        tree << parse_type(tokenizer, tree)

        tree << parse_optional(tokenizer, :kMINUS2) do
          parse_comment(tokenizer)
        end

        tree
      end

      #: (Tokenizer) -> AST::Tree
      def parse_block_type(tokenizer)
        tree = AST::Tree.new(:block_type)

        tokenizer.consume_token!(:kAMP, tree: tree)
        tokenizer.consume_token(:tLVAR, tree: tree)
        tokenizer.consume_token(:kCOLON, tree: tree)

        tokenizer.consume_token(:kQUESTION, tree: tree)

        unless (string = tokenizer.skip_to_comment()).empty?
          tree << [:tBLOCKSTR, string]
        else
          tree << nil
        end

        tree << parse_optional(tokenizer, :kMINUS2) do
          parse_comment(tokenizer)
        end

        tree
      end
    end
  end
end
