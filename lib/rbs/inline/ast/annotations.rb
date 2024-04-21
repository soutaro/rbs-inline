module RBS
  module Inline
    module AST
      module Annotations
        class Base
          attr_reader :source #:: CommentLines
          attr_reader :tree #:: Tree

          # @rbs tree: Tree
          # @rbs source: CommentLines
          # @rbs return: void
          def initialize(tree, source)
            @tree = tree
            @source = source
          end
        end

        class VarType < Base
          attr_reader :name #:: Symbol?

          attr_reader :type #:: Types::t?

          attr_reader :comment #:: String?

          # @rbs override
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

          #:: () -> bool
          def complete?
            if name && type
              true
            else
              false
            end
          end
        end

        class ReturnType < Base
          attr_reader :type #:: Types::t?

          attr_reader :comment #:: String?

          # @rbs override
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

          # @rbs return: bool
          def complete?
            if type
              true
            else
              false
            end
          end
        end

        # `#:: TYPE`
        #
        class Assertion < Base
          attr_reader :type #:: Types::t | MethodType | nil

          def initialize(tree, source)
            @source = source
            @tree = tree

            @type = tree.nth_method_type?(1) || tree.nth_type?(1)
          end

          # @rbs return: bool
          def complete?
            if type
              true
            else
              false
            end
          end
        end

        # `#[TYPE, ..., TYPE]`
        #
        class Application < Base
          attr_reader :types #:: Array[Types::t]?

          # @rbs override
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

          # @rbs return: bool
          def complete?
            types ? true : false
          end
        end

        # `# @rbs %a{a} %a{a} ...`
        class RBSAnnotation < Base
          attr_reader :contents #:: Array[String]

          # @rbs override
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

        # `# @rbs skip`
        #
        class Skip < Base
          # @rbs override
          def initialize(tree, source)
            @tree = tree
            @source = source
          end
        end

        # `# @rbs inherits T`
        #
        class Inherits < Base
          attr_reader :super_name #:: TypeName?
          attr_reader :args #:: Array[Types::t]?

          # @rbs override
          def initialize(tree, source)
            @tree = tree
            @source = source

            inherits = tree.nth_tree!(1)
            if super_type = inherits.nth_type(1)
              if super_type.is_a?(Types::ClassInstance)
                @super_name = super_type.name
                @args = super_type.args
              end
            end
          end
        end

        # `# @rbs override`
        #
        # Specify the method types as `...` (overriding super class method)
        #
        class Override < Base
          # @rbs override
          def initialize(tree, source)
            @tree = tree
            @source = source
          end
        end
      end
    end
  end
end
