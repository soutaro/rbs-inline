# rbs_inline: enabled

module RBS
  module Inline
    module AST
      # CommentLines represents consecutive comments, providing a mapping from locations in `#string` to a pair of a comment and its offset
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
        attr_reader :comments #: Array[Prism::Comment]

        # @rbs comments: Array[Prism::Comment]
        def initialize(comments) #: void
          @comments = comments
        end

        def lines #: Array[String]
          comments.map {|comment| comment.location.slice }
        end

        def string #: String
          comments.map {|comment| comment.location.slice[1..] || "" }.join("\n")
        end

        # Translates the cursor index of `#string` into the cursor index of a specific comment object
        #
        # @rbs index: Integer
        # @rbs return: [Prism::Comment, Integer]?
        def comment_location(index)
          comments.each do |comment|
            comment_length = comment.location.length

            if index + 1 <= comment_length
              return [comment, index + 1]
            else
              index -= comment_length - 1
              index -= 1 # newline
              return if index < 0
            end
          end

          nil
        end
      end
    end
  end
end
