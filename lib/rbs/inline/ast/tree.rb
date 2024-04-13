module RBS
  module Inline
    module AST
      class Tree
        attr_reader :trees
        attr_reader :type
        attr_reader :non_trivia_trees

        def initialize(type)
          @type = type
          @trees = []
          @non_trivia_trees = []
        end

        def <<(tok)
          trees << tok
          unless tok.is_a?(Array) && tok[0] == :tWHITESPACE
            non_trivia_trees << tok
          end
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
          when Array, Tree, MethodType
            raise
          else
            tok
          end
        end

        def nth_type?(index)
          tok = non_trivia_trees[index]
          case tok
          when Array, Tree, nil, MethodType
            nil
          else
            tok
          end
        end

        def nth_type!(index)
          nth_type(index) || raise
        end

        def nth_method_type(index)
          tok = non_trivia_trees[index]
          case tok
          when MethodType, nil
            tok
          else
            raise
          end
        end

        def nth_method_type?(index)
          tok = non_trivia_trees[index]
          case tok
          when MethodType
            tok
          else
            nil
          end
        end

        def nth_method_type!(index)
          nth_method_type(index) || raise
        end
      end
    end
  end
end
