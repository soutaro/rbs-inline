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
      end
    end
  end
end
