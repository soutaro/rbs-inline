module RBS
  module Inline
    class AnnotationParser
      class ParsingResult
        attr_reader :comments
        attr_reader :annotations
        attr_reader :first_comment_offset

        def initialize(first_comment)
          @comments = [first_comment]
          @annotations = []
          content = first_comment.location.slice
          index = content.index(/[^#\s]/) || content.size
          @first_comment_offset = index
        end

        def line_range
          first = comments.first or raise
          last = comments.last or raise

          first.location.start_line .. last.location.end_line
        end

        def <<(comment)
          @comments << comment
          self
        end

        def last_comment
          comments.last or raise
        end

        def add_comment(comment)
          if last_comment.location.end_line + 1 == comment.location.start_line
            if last_comment.location.start_column == comment.location.start_column
              comments << comment
              self
            end
          end
        end

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

        def content
          content = +""
          lines.each do |line, _|
            content << line
            content << "\n"
          end
          content
        end
      end

      attr_reader :input

      def initialize(input)
        @input = input
      end

      def self.parse(input)
        new(input).parse
      end

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

      def each_annotation_paragraph(result)
        lines = result.lines

        while true
          line, comment = lines.shift
          break unless line && comment

          next_line, next_comment = lines.first

          if line.start_with?('@rbs')
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
        attr_reader :scanner
        attr_reader :current_token

        def initialize(scanner)
          @scanner = scanner
          @current_token = nil
        end

        def advance(tree)
          last = current_token

          case
          when s = scanner.scan(/\s+/)
            tree << [:tWHITESPACE, s] if tree
            advance(tree)
          when s = scanner.scan(/@rbs/)
            @current_token = [:kRBS, s]
          when s = scanner.scan(/[a-z]\w*/)
            @current_token = [:tLVAR, s]
          when s = scanner.scan(/:/)
            @current_token = [:kCOLON, s]
          when s = scanner.scan(/--/)
            @current_token = [:kMINUS2, s]
          else
            @current_token = nil
          end

          last
        end

        def type?(type)
          if current_token && current_token[0] == type
            true
          else
            false
          end
        end

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

      def parse_annotation(comments)
        scanner = StringScanner.new(comments.string)
        tokenizer = Tokenizer.new(scanner)

        tree = AST::Tree.new(:rbs_annotation)
        tokenizer.advance(tree)

        raise unless tokenizer.type?(:kRBS)

        tree << tokenizer.current_token

        tokenizer.advance(tree)

        case
        when tokenizer.type?(:tLVAR)
          tree << parse_var_decl(tokenizer)
          AST::Annotations::VarType.new(tree, comments)
        end
      end

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

      def parse_comment(tokenizer)
        tree = AST::Tree.new(:comment)

        if tokenizer.type?(:kMINUS2)
          tree << tokenizer.current_token
          tokenizer.scanner.scan(/.*/)
          tree << [:tCOMMENT, tokenizer.scanner.matched || ""]
        else
          tree << nil
          tree << nil
        end

        tokenizer.scanner.skip(/.*/)

        tree
      end

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
        content = tokenizer.skip_to_comment || ""
        tree = AST::Tree.new(:type_syntax_error)
        tree << [:tSOURCE, content]
        tree
      end
    end
  end
end
