module RBS
  module Inline
    module AST
      module Annotations
        class Base
          attr_reader :source
          attr_reader :tree
        end

        class VarType < Base
          attr_reader :name
          attr_reader :type
          attr_reader :comment

          def initialize(tree, source)
            @tree = tree
            @source = source

            lvar_tree = tree.nth_tree!(1)

            if lvar = lvar_tree.nth_token(0)
              @name = lvar[1].to_sym
            end

            if type = lvar_tree.nth_type?(2)
              @type = type
            end

            if comment = lvar_tree.nth_tree(3)
              @comment = comment.to_s
            end
          end

          def complete?
            if name && type
              true
            else
              false
            end
          end
        end

        class ReturnType < Base
          attr_reader :type

          attr_reader :comment

          def initialize(tree, source)
            @tree = tree
            @source = source

            return_type_decl = tree.nth_tree!(1)

            if type = return_type_decl.nth_type?(2)
              @type = type
            end

            if comment = return_type_decl.nth_tree(3)
              @comment = comment.to_s
            end
          end

          def complete?
            if type
              true
            else
              false
            end
          end
        end

        class Assertion < Base
          attr_reader :type

          def initialize(tree, source)
            @source = source
            @tree = tree

            @type = tree.nth_method_type?(1) || tree.nth_type?(1)
          end

          def complete?
            if type
              true
            else
              false
            end
          end
        end

        class Application < Base
          attr_reader :types

          def initialize(tree, source)
            @tree = tree
            @source = source

            if ts = tree.nth_tree(0)
              if types = ts.nth_tree(1)
                @types = types.non_trivia_trees.each_slice(2).map do |type, comma|
                  # @type break: nil

                  case type
                  when AST::Tree, MethodType, Array, nil
                    break
                  else
                    type
                  end
                end
              end
            end
          end

          def complete?
            types ? true : false
          end
        end

        class RBSAnnotation < Base
          attr_reader :contents

          def initialize(tree, comments)
            @source = comments
            @tree = tree

            annots = tree.nth_tree!(1)
            @contents = annots.non_trivia_trees.map do |token|
              raise unless token.is_a?(Array)
              token[1]
            end
          end
        end

        class Skip < Base
          def initialize(tree, source)
            @tree = tree
            @source = source
          end
        end
      end
    end
  end
end
