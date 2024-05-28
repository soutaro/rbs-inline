# rbs_inline: enabled

module RBS
  module Inline
    module AST
      # CommentLines represents consecutive comments
      #
      # The comments construct one String.
      #
      # ```ruby
      # # Hello       <-- Comment1
      # # World       <-- Comment2
      # ```
      #
      # We want to get a String of comment1 and comment2, `"Hello\nWorld".
      # And want to translate a location in the string into the location in comment1 and comment2.
      #
      class CommentLines
        attr_reader :comments #:: Array[[Prism::Comment, Integer]]

        # @rbs comments: Array[Prism::Comment]
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

        def string #:: String
          comments.map {|comment, offset| comment.location.slice[offset..] }.join("\n")
        end

        # @rbs index: Integer
        # @rbs returns [Prism::Comment, Integer]?
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
