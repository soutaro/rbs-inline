# rbs_inline: enabled

module RBS
  module Inline
    module AST
      module Annotations
        # @rbs!
        #   type t = VarType
        #          | ReturnType
        #          | Use
        #          | Inherits
        #          | Generic
        #          | ModuleSelf
        #          | Skip
        #          | Assertion
        #          | Application
        #          | RBSAnnotation
        #          | Override
        #          | IvarType
        #          | Yields
        #          | Embedded
        #          | Method
        #        #  | Def
        #        #  | AttrReader | AttrWriter | AttrAccessor
        #        #  | Include | Extend | Prepend
        #        #  | Alias

        class Base
          attr_reader :source #:: CommentLines
          attr_reader :tree #:: Tree

          # @rbs tree: Tree
          # @rbs source: CommentLines
          # @rbs returns void
          def initialize(tree, source)
            @tree = tree
            @source = source
          end
        end

        class VarType < Base
          attr_reader :name #:: Symbol

          attr_reader :type #:: Types::t?

          attr_reader :comment #:: String?

          # @rbs override
          def initialize(tree, source)
            @tree = tree
            @source = source

            lvar_tree = tree.nth_tree!(1)

            # :tLVAR doesn't have `!` prefix
            # :tELVAR has `!` prefix to escape keywords
            @name = lvar_tree.nth_token!(0)[1].delete_prefix("!").to_sym

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

        # `@rbs returns T`
        class ReturnType < Base
          attr_reader :type #:: Types::t?

          attr_reader :comment #:: String?

          # @rbs override
          def initialize(tree, source)
            @tree = tree
            @source = source

            return_type_decl = tree.nth_tree!(1)

            if type = return_type_decl.nth_type?(1)
              @type = type
            end

            if comment = return_type_decl.nth_tree(2)
              @comment = comment.to_s
            end
          end

          # @rbs returns bool
          def complete?
            if type
              true
            else
              false
            end
          end
        end

        # `@rbs @foo: T` or `@rbs self.@foo: T`
        #
        class IvarType < Base
          attr_reader :name #:: Symbol

          attr_reader :type #:: Types::t?

          attr_reader :class_instance #:: bool

          attr_reader :comment #:: String?

          # @rbs override
          def initialize(tree, source)
            @tree = tree
            @source = source

            ivar_tree = tree.nth_tree!(1)
            @class_instance = ivar_tree.nth_token?(0).is_a?(Array)
            @name = ivar_tree.nth_token!(2).last.to_sym
            @type = ivar_tree.nth_type?(4)

            if comment = ivar_tree.nth_tree(5)
              @comment = comment.to_s
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

          # @rbs returns bool
          def complete?
            if type
              true
            else
              false
            end
          end

          # Returns a type if it's type
          #
          def type? #:: Types::t?
            case type
            when MethodType, nil
              nil
            else
              type
            end
          end

          # Returns a method type if it's a method type
          #
          def method_type? #:: MethodType?
            case type
            when MethodType
              type
            else
              nil
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

          # @rbs returns bool
          def complete?
            types ? true : false
          end
        end

        # `# @rbs yields () -> void -- Comment`
        #
        class Yields < Base
          # The type of block
          #
          # * Types::Block when syntactically correct input is given
          # * String when syntax error is reported
          # * `nil` when nothing is given
          #
          attr_reader :block_type #:: Types::Block | String | nil

          # The content of the comment or `nil`
          #
          attr_reader :comment #:: String?

          # If `[optional]` token is inserted just after `yields` token
          #
          # The Types::Block instance has correct `required` attribute based on the `[optional]` token.
          # This is for the other cases, syntax error or omitted.
          #
          attr_reader :optional #:: bool

          # @rbs override
          def initialize(tree, comments)
            @tree = tree
            @source = comments

            yields_tree = tree.nth_tree!(1)
            @optional = yields_tree.nth_token?(1).is_a?(Array)
            if block_token = yields_tree.nth_token(2)
              block_src = block_token[1]
              proc_src = "^" + block_src
              proc_type = ::RBS::Parser.parse_type(proc_src, require_eof: true) rescue RBS::ParsingError
              if proc_type.is_a?(Types::Proc)
                @block_type = Types::Block.new(
                  type: proc_type.type,
                  required: !optional,
                  self_type: proc_type.self_type
                )
              else
                @block_type = block_src
              end
            end

            @comment = yields_tree.nth_tree?(3)&.to_s
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

        # `# @rbs use [USES]`
        class Use < Base
          attr_reader :clauses #:: Array[RBS::AST::Directives::Use::clause]

          # @rbs override
          def initialize(tree, source)
            @tree = tree
            @source = source

            @clauses = []

            tree.nth_tree!(1).tap do |use_tree|
              _, *clause_pairs = use_tree.non_trivia_trees
              clause_pairs.each_slice(2) do |clause, _comma|
                if clause.is_a?(Tree)
                  *tokens, last_token = clause.non_trivia_trees
                  token_strs = tokens.map do |tok|
                    if tok.is_a?(Array)
                      tok[1]
                    else
                      raise
                    end
                  end

                  case last_token
                  when Array
                    # `*` clause
                    namespace = Namespace(token_strs.join)
                    @clauses << RBS::AST::Directives::Use::WildcardClause.new(
                      namespace: namespace,
                      location: nil
                    )
                  when Tree, nil
                    if last_token
                      if new_name_token = last_token.nth_token(1)
                        new_name = new_name_token[1].to_sym
                      end
                    end

                    typename = TypeName(token_strs.join)
                    @clauses << RBS::AST::Directives::Use::SingleClause.new(
                      type_name: typename,
                      new_name: new_name,
                      location: nil
                    )
                  end
                end
              end
            end
          end
        end

        # `# @rbs module-self [MODULE_SELF]`
        class ModuleSelf < Base
          attr_reader :constraint #:: RBS::AST::Declarations::Module::Self?

          attr_reader :comment #:: String?

          # @rbs override
          def initialize(tree, source)
            @tree = tree
            @source = source

            module_self = tree.nth_tree!(1)
            type = module_self.nth_type?(1)

            case type
            when Types::ClassInstance, Types::Interface
              @constraint = RBS::AST::Declarations::Module::Self.new(
                name: type.name,
                args: type.args,
                location: nil
              )
            end

            if comment = module_self.nth_tree(2)
              @comment = comment.to_s
            end
          end
        end

        # `# @rbs generic [type param]`
        #
        # ```rb
        # # @rbs generic X
        # # @rbs generic in Y
        # # @rbs generic unchecked out Z < String -- Comment here
        # ```
        #
        class Generic < Base
          # TypeParam object or `nil` if syntax error
          #
          attr_reader :type_param #:: RBS::AST::TypeParam?

          attr_reader :comment #:: String?

          # @rbs override
          def initialize(tree, source)
            @tree = tree
            @source = source

            generic_tree = tree.nth_tree!(1)
            unchecked = generic_tree.nth_token?(1) != nil
            inout =
              case generic_tree.nth_token?(2)&.[](0)
              when nil
                :invariant
              when :kIN
                :contravariant
              when :kOUT
                :covariant
              end #: RBS::AST::TypeParam::variance

            name = generic_tree.nth_token?(3)&.last

            if bound = generic_tree.nth_tree?(4)
              if type = bound.nth_type?(1)
                case type
                when Types::ClassSingleton, Types::ClassInstance, Types::Interface
                  upper_bound = type
                end
              end
            end

            if name
              @type_param = RBS::AST::TypeParam.new(
                name: name.to_sym,
                variance: inout,
                upper_bound: upper_bound,
                location: nil
              ).unchecked!(unchecked)
            end

            if comment = generic_tree.nth_tree?(5)
              @comment = comment.to_s
            end
          end
        end

        # `# @rbs!` annotation
        class Embedded < Base
          attr_reader :content #:: String

          # @rbs override
          def initialize(tree, source)
            @tree = tree
            @source = source

            @content = tree.nth_token!(1)[1]
          end
        end

        # `@rbs METHOD-TYPE``
        #
        class Method < Base
          attr_reader :type #:: MethodType?

          attr_reader :method_type_source #:: String

          # @rbs override
          def initialize(tree, source)
            @tree = tree
            @source = source

            case type = tree.nth_tree!(1).non_trivia_trees[0]
            when MethodType
              @type = type
              @method_type_source = type.location&.source || raise
            else
              @type = nil
              @method_type_source = type.to_s
            end
          end
        end
      end
    end
  end
end
