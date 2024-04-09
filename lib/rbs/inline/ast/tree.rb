module RBS
  module Inline
    module AST
      class Tree
        attr_reader :trees
        attr_reader :type

        def initialize(type)
          @type = type
          @trees = []
        end

        def <<(tok)
          trees << tok
          self
        end

        def to_s
          buf = +""
          
          trees.each do |tree|
            case tree
            when Array
              buf << tree[1]
            when Tree
              buf << tree.to_s
            when nil
            else
              loc = tree.location or raise
              buf << loc.source
            end
          end

          buf
        end

        def non_trivia_trees
          trees.select do |tree|
            if tree.is_a?(Array)
              tree[0] != :tWHITESPACE
            else
              true
            end
          end
        end

        def nth_token(index)
          tok = non_trivia_trees[index]
          case tok
          when Array, nil
            tok
          else
            raise
          end
        end

        def nth_token?(index)
          tok = non_trivia_trees[index]
          case tok
          when Array
            tok
          else
            nil
          end
        end

        def nth_token!(index)
          nth_token(index) || raise
        end

        def nth_tree(index)
          tok = non_trivia_trees[index]
          case tok
          when Tree, nil
            tok
          else
            raise
          end
        end

        def nth_tree?(index)
          tok = non_trivia_trees[index]
          case tok
          when Tree
            tok
          else
            nil
          end
        end

        def nth_tree!(index)
          nth_tree(index) || raise
        end


        def nth_type(index)
          tok = non_trivia_trees[index]
          case tok
          when Array, Tree
            raise
          else
            tok
          end
        end

        def nth_type?(index)
          tok = non_trivia_trees[index]
          case tok
          when Array, Tree, nil
            nil
          else
            tok
          end
        end

        def nth_type!(index)
          nth_type(index) || raise
        end
      end
    end
  end
end
