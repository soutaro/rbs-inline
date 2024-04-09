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

      def parse_annotation(comments)
        scanner = StringScanner.new(comments.string)

        AST::Annotations::VarType.new(nil, nil, comments)
      end
    end
  end
end
