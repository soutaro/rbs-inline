module RBS
  module Inline
    module AST
      class CommentLines
        attr_reader :comments

        def initialize(comments)
          offsets = comments.map do |comment|
            comment.location.slice.index(/[^#\s]/) || 1
          end
          first_offset = offsets[0]

          @comments = comments.map.with_index do |comment, index|
            offset = offsets[index]
            offset = first_offset if offset > first_offset

            [comment, offset]
          end
        end

        def string
          buffer = +""

          comments.each do |comment, offset|
            buffer << (comment.location.slice[offset..] || "")
            buffer << "\n"
          end

          buffer
        end

        def comment_location(index)
          comments.each do |comment, offset|
            comment_length = comment.location.length

            if index + offset <= comment_length
              return [comment, index + offset]
            else
              index = index - comment_length + offset - 1
              return if index < 0
            end
          end

          nil
        end
      end
    end
  end
end
