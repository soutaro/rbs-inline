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
        end
      end
    end
  end
end
