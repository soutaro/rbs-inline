# rbs_inline: enabled

module RBS
  module Inline
    class AnnotationParser
      class ParsingResult
        attr_reader :comments #:: Array[Prism::Comment]
        attr_reader :annotations #:: Array[AST::Annotations::t]
        attr_reader :first_comment_offset #:: Integer

        # @rbs first_comment: Prism::Comment
        def initialize(first_comment)
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

        # @rbs return: Array[[String, Prism::Comment]]
        def lines
          comments.map do |comment|
            slice = comment.location.slice
            index = slice.index(/[^#\s]/) || slice.size
            string = if index > first_comment_offset
              slice[first_comment_offset..] || ""
            else
              slice[index..] || ""
            end
            [string, comment]
          end
        end

        # @rbs return: String
        def content
          lines.map(&:first).join("\n")
        end
      end

      attr_reader :input #:: Array[Prism::Comment]

      # @rbs input: Array[Prism::Comment]
      def initialize(input)
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
          each_annotation_paragraph(result) do |comments|
            if annot = parse_annotation(AST::CommentLines.new(comments))
              result.annotations << annot
            end
          end
        end

        results
      end

      private

      # @rbs result: ParsingResult
      # @rbs block: ^(Array[Prism::Comment]) -> void
      # @rbs return: void
      def each_annotation_paragraph(result, &block)
        lines = result.lines

        while true
          line, comment = lines.shift
          break unless line && comment

          next_line, next_comment = lines.first

          possible_annotation = false
          possible_annotation ||= line.start_with?('@rbs')
          possible_annotation ||= comment.location.slice.start_with?("#::", "#[")

          if possible_annotation
            line_offset = line.index(/\S/) || raise

            comments = [comment]

            while true
              break unless next_line && next_comment
              next_offset = next_line.index(/\S/) || 0
              break unless next_offset > line_offset

              comments << next_comment
              lines.shift

              next_line, next_comment = lines.first
            end

            yield comments
          end
        end
      end

      class Tokenizer
        attr_reader :scanner #:: StringScanner
        attr_reader :current_token #:: token?

        KEYWORDS = {
          "@rbs" => :kRBS,
          "return" => :kRETURN,
          "inherits" => :kINHERITS,
          "as" => :kAS,
          "override" => :kOVERRIDE,
          "use" => :kUSE,
        } #:: Hash[String, Symbol]
        KW_RE = /#{Regexp.union(KEYWORDS.keys)}\b/

        PUNCTS = {
          "::" => :kCOLON2,
          ":" => :kCOLON,
          "[" => :kLBRACKET,
          "]" => :kRBRACKET,
          "," => :kCOMMA,
          "*" => :kSTAR,
          "--" => :kMINUS2,
        } #:: Hash[String, Symbol]
        PUNCTS_RE = Regexp.union(PUNCTS.keys)

        # @rbs scanner: StringScanner
        # @rbs return: void
        def initialize(scanner)
          @scanner = scanner
          @current_token = nil
        end

        # @rbs tree: AST::Tree
        # @rbs return: token?
        def advance(tree)
          last = current_token

          case
          when s = scanner.scan(/\s+/)
            tree << [:tWHITESPACE, s] if tree
            advance(tree)
          when s = scanner.scan(PUNCTS_RE)
            @current_token = [PUNCTS.fetch(s), s]
          when s = scanner.scan(KW_RE)
            @current_token = [KEYWORDS.fetch(s), s]
          when s = scanner.scan(/[A-Z]\w*/)
            @current_token = [:tUIDENT, s]
          when s = scanner.scan(/_[A-Z]\w*/)
            @current_token = [:tIFIDENT, s]
          when s = scanner.scan(/[a-z]\w*/)
            @current_token = [:tLVAR, s]
          when s = scanner.scan(/%a\{[^}]+\}/)
            @current_token = [:tANNOTATION, s]
          when s = scanner.scan(/%a\[[^\]]+\]/)
            @current_token = [:tANNOTATION, s]
          when s = scanner.scan(/%a\([^)]+\)/)
            @current_token = [:tANNOTATION, s]
          else
            @current_token = nil
          end

          last
        end

        # Test if current token has specified `type`
        #
        # @rbs type: Array[Symbol]
        # @rbs return: bool
        def type?(*type)
          type.any? { current_token && current_token[0] == _1 }
        end

        # Reset the current_token to incoming comment `--`
        #
        # Reset to the end of the input if `--` token cannot be found.
        #
        # @rbs return: String -- String that is skipped
        def skip_to_comment
          return "" if type?(:kMINUS2)

          rest = scanner.matched || ""

          if scanner.scan_until(/--/)
            @current_token = [:kMINUS2, "--"]
            rest + scanner.pre_match
          else
            rest += scanner.scan(/.*/) || ""
            rest
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

        case
        when tokenizer.type?(:kRBS)
          tree << tokenizer.current_token

          tokenizer.advance(tree)

          case
          when tokenizer.type?(:tLVAR)
            t =  parse_var_decl(tokenizer)
            tree << t

            if t.nth_token(0)&.[](1) == "skip" && t.non_trivia_trees[1] == nil && t.non_trivia_trees[2] == nil
              AST::Annotations::Skip.new(tree, comments)
            else
              AST::Annotations::VarType.new(tree, comments)
            end

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
          end
        when tokenizer.type?(:kCOLON2)
          tree << tokenizer.current_token
          tokenizer.advance(tree)
          tree << parse_type_method_type(tokenizer, tree)
          AST::Annotations::Assertion.new(tree, comments)
        when tokenizer.type?(:kLBRACKET)
          tree << parse_type_app(tokenizer)
          AST::Annotations::Application.new(tree, comments)
        end
      end

      # @rbs tokenizer: Tokenizer
      # @rbs return: AST::Tree
      def parse_var_decl(tokenizer)
        tree = AST::Tree.new(:var_decl)

        if tokenizer.type?(:tLVAR)
          tree << tokenizer.current_token
          tokenizer.advance(tree)
        else
          tree << nil
        end

        if tokenizer.type?(:kCOLON)
          tree << tokenizer.current_token
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

        if tokenizer.type?(:kRETURN)
          tree << tokenizer.current_token
          tokenizer.advance(tree)
        else
          tree << nil
        end

        if tokenizer.type?(:kCOLON)
          tree << tokenizer.current_token
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
      def parse_comment(tokenizer)
        tree = AST::Tree.new(:comment)

        if tokenizer.type?(:kMINUS2)
          tree << tokenizer.current_token
          rest = tokenizer.scanner.rest || ""
          tokenizer.scanner.terminate
          tree << [:tCOMMENT, rest]
        else
          tree << nil
          tree << nil
        end

        tree
      end

      # @rbs tokenizer: Tokenizer
      # @rbs return: AST::Tree
      def parse_type_app(tokenizer)
        tree = AST::Tree.new(:tapp)

        if tokenizer.type?(:kLBRACKET)
          tree << tokenizer.current_token
          tokenizer.advance(tree)
        end

        types = AST::Tree.new(:types)
        while true
          type = parse_type(tokenizer, types)
          types << type

          break unless type
          break if type.is_a?(AST::Tree)

          if tokenizer.type?(:kCOMMA)
            types << tokenizer.current_token
            tokenizer.advance(types)
          end

          if tokenizer.type?(:kRBRACKET)
            break
          end
        end
        tree << types

        if tokenizer.type?(:kRBRACKET)
          tree << tokenizer.current_token
          tokenizer.advance(tree)
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
        range = (tokenizer.scanner.charpos - (tokenizer.scanner.matched_size || 0) ..)
        begin
          if type = RBS::Parser.parse_method_type(buffer, range: range, require_eof: false)
            loc = type.location or raise
            size = loc.end_pos - loc.start_pos
            (size - (tokenizer.scanner.matched_size || 0)).times do
              tokenizer.scanner.skip(/./)
            end
            tokenizer.advance(parent_tree)
            type
          else
            tokenizer.advance(parent_tree)
            nil
          end
        rescue RBS::ParsingError
          begin
            if type = RBS::Parser.parse_type(buffer, range: range, require_eof: false)
              loc = type.location or raise
              size = loc.end_pos - loc.start_pos
              (size - (tokenizer.scanner.matched_size || 0)).times do
                tokenizer.scanner.skip(/./)
              end
              tokenizer.advance(parent_tree)
              type
            else
              tokenizer.advance(parent_tree)
              nil
            end
          rescue RBS::ParsingError
            content = (tokenizer.scanner.matched || "") + (tokenizer.scanner.rest || "")
            tree = AST::Tree.new(:type_syntax_error)
            tree << [:tSOURCE, content]
            tokenizer.scanner.terminate
            tree
          end
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
      # Integer[ -- Foo       # => Returns a tree for `Integer[`, tokenizer has `--` as its curren token
      # Integer[ Foo          # => Returns a tree for `Integer[ Foo`, tokenizer is at the end of the input
      # ```
      #
      # @rbs tokenizer: Tokenizer
      # @rbs parent_tree: AST::Tree
      # @rbs return: Types::t | AST::Tree | nil
      def parse_type(tokenizer, parent_tree)
        buffer = RBS::Buffer.new(name: "", content: tokenizer.scanner.string)
        range = (tokenizer.scanner.charpos - (tokenizer.scanner.matched_size || 0) ..)
        if type = RBS::Parser.parse_type(buffer, range: range, require_eof: false)
          loc = type.location or raise
          size = loc.end_pos - loc.start_pos
          (size - (tokenizer.scanner.matched_size || 0)).times do
            tokenizer.scanner.skip(/./)
          end
          tokenizer.advance(parent_tree)
          type
        else
          tokenizer.advance(parent_tree)
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
          tree << tokenizer.current_token
          tokenizer.advance(tree)
        end

        tree
      end

      # @rbs tokznier: Tokenizer
      # @rbs return: AST::Tree
      def parse_inherits(tokenizer)
        tree = AST::Tree.new(:rbs_inherits)

        if tokenizer.type?(:kINHERITS)
          tree << tokenizer.current_token
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
          tree << tokenizer.current_token
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
          tree << tokenizer.current_token
          tokenizer.advance(tree)
        end

        while tokenizer.type?(:kCOLON2, :tUIDENT, :tIFIDENT, :tLVAR)
          tree << parse_use_clause(tokenizer)

          if tokenizer.type?(:kCOMMA)
            tree << tokenizer.advance(tree)
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
          tree << tokenizer.current_token
          tokenizer.advance(tree)
        end

        while true
          case
          when tokenizer.type?(:tUIDENT)
            tree << tokenizer.advance(tree)

            case
            when tokenizer.type?(:kCOLON2)
              tree << tokenizer.advance(tree)
            else
              break
            end
          else
            break
          end
        end

        case
        when tokenizer.type?(:tLVAR)
          tree << tokenizer.advance(tree)
        when tokenizer.type?(:tIFIDENT)
          tree << tokenizer.advance(tree)
        when tokenizer.type?(:kSTAR)
          tree << tokenizer.advance(tree)
          return tree
        end

        if tokenizer.type?(:kAS)
          as_tree = AST::Tree.new(:as)

          as_tree << tokenizer.advance(as_tree)

          if tokenizer.type?(:tLVAR, :tIFIDENT, :tUIDENT)
            as_tree <<tokenizer.advance(as_tree)
          else
            as_tree << nil
          end

          tree << as_tree
        else
          tree << nil
        end

        tree
      end
    end
  end
end
