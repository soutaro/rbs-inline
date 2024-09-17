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
        #          | MethodTypeAssertion | TypeAssertion | SyntaxErrorAssertion | Dot3Assertion
        #          | Application
        #          | RBSAnnotation
        #          | Override
        #          | IvarType
        #          | Embedded
        #          | Method
        #          | SplatParamType
        #          | DoubleSplatParamType
        #          | BlockType
        #          | ModuleDecl
        #          | ClassDecl
        #        #  | Def
        #        #  | AttrReader | AttrWriter | AttrAccessor
        #        #  | Include | Extend | Prepend
        #        #  | Alias

        module Utils
          # @rbs (Tree) -> RBS::AST::TypeParam?
          def translate_type_param(tree)
            unchecked = tree.nth_token?(0) != nil
            inout =
              case tree.nth_token?(1)&.[](0)
              when nil
                :invariant
              when :kIN
                :contravariant
              when :kOUT
                :covariant
              end #: RBS::AST::TypeParam::variance

            name = tree.nth_token?(2)&.last

            if bound = tree.nth_tree?(3)
              if type = bound.nth_type?(1)
                case type
                when Types::ClassSingleton, Types::ClassInstance, Types::Interface
                  upper_bound = type
                end
              end
            end

            if name
              RBS::AST::TypeParam.new(
                name: name.to_sym,
                variance: inout,
                upper_bound: upper_bound,
                location: nil
              ).unchecked!(unchecked)
            end
          end

          # @rbs (Types::t) -> RBS::AST::Declarations::Class::Super?
          def translate_super_class(type)
            case type
            when Types::ClassInstance
              RBS::AST::Declarations::Class::Super.new(
                name: type.name,
                args: type.args,
                location: nil
              )
            end
          end

          # Assumes the tree is generated through `#parse_module_name`
          #
          # Returns a type name, or `nil` if the tree is something invalid.
          #
          # @param tree -- A tree object that is generated through `#parse_module_name`
          #
          # @rbs (AST::Tree) -> TypeName?
          def translate_type_name(tree)
            tokens = tree.non_trivia_trees

            absolute = tokens.shift
            path = [] #: Array[Symbol]

            tokens.each_slice(2) do |name, colon2|
              if colon2
                name or return nil
                name.is_a?(Array) or return nil

                path << name[1].to_sym
              end
            end

            last_token = tokens.pop
            last_token.is_a?(Array) or return nil
            name = last_token[1].to_sym

            namespace = Namespace.new(path: path, absolute: absolute ? true : false)
            TypeName.new(namespace: namespace, name: name)
          end
        end

        class Base
          attr_reader :source #: CommentLines
          attr_reader :tree #: Tree

          # @rbs tree: Tree
          # @rbs source: CommentLines
          # @rbs return: void
          def initialize(tree, source)
            @tree = tree
            @source = source
          end
        end

        class VarType < Base
          attr_reader :name #: Symbol

          attr_reader :type #: Types::t?

          attr_reader :comment #: String?

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

          #: () -> bool
          def complete?
            if name && type
              true
            else
              false
            end
          end
        end

        class SpecialVarTypeAnnotation < Base
          attr_reader :name #: Symbol?

          attr_reader :type #: Types::t?

          attr_reader :comment #: String?

          attr_reader :type_source #: String

          # @rbs override
          def initialize(tree, source)
            @tree = tree
            @source = source

            annotation = tree.nth_tree!(1)

            if name = annotation.nth_token?(1)
              @name = name[1].to_sym
            end

            if type = annotation.nth_type?(3)
              @type = type
              @type_source = type.location&.source || raise
            else
              @type = nil
              @type_source = annotation.nth_tree!(3)&.to_s || raise
            end

            if comment = annotation.nth_tree(4)
              @comment = comment.to_s
            end
          end
        end

        # `@rbs *x: T`
        class SplatParamType < SpecialVarTypeAnnotation
        end

        # `@rbs` **x: T
        class DoubleSplatParamType < SpecialVarTypeAnnotation
        end

        # `@rbs &block: METHOD-TYPE` or `@rbs &block: ? METHOD-TYPE`
        class BlockType < Base
          attr_reader :name #: Symbol?

          attr_reader :type #: Types::Block?

          attr_reader :comment #: String?

          attr_reader :type_source #: String

          # @rbs override
          def initialize(tree, source)
            @tree = tree
            @source = source

            annotation = tree.nth_tree!(1)

            if name = annotation.nth_token?(1)
              @name = name[1].to_sym
            end

            optional = annotation.nth_token?(3)

            if type_token = annotation.nth_token?(4)
              block_src = type_token[1]

              proc_type = ::RBS::Parser.parse_type("^" + block_src, require_eof: true) rescue RBS::ParsingError
              if proc_type.is_a?(Types::Proc)
                @type = Types::Block.new(
                  type: proc_type.type,
                  required: !optional,
                  self_type: proc_type.self_type
                )
              end

              @type_source = block_src
            else
              @type = nil
              @type_source = ""
            end

            if comment = annotation.nth_tree(5)
              @comment = comment.to_s
            end
          end
        end

        # `@rbs return: T`
        class ReturnType < Base
          attr_reader :type #: Types::t?

          attr_reader :comment #: String?

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

        # `@rbs @foo: T` or `@rbs self.@foo: T`
        #
        class IvarType < Base
          attr_reader :name #: Symbol

          attr_reader :type #: Types::t?

          attr_reader :class_instance #: bool

          attr_reader :comment #: String?

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

        class MethodTypeAssertion < Base
          attr_reader :method_type #: MethodType

          # @rbs override
          def initialize(tree, source)
            @source = source
            @tree = tree

            @method_type = tree.nth_method_type!(1)
          end

          def type_source #: String
            method_type.location&.source || raise
          end
        end

        class TypeAssertion < Base
          attr_reader :type #: Types::t

          # @rbs override
          def initialize(tree, source)
            @source = source
            @tree = tree

            @type = tree.nth_type!(1)
          end

          def type_source #: String
            type.location&.source || raise
          end
        end

        class SyntaxErrorAssertion < Base
          attr_reader :error_string #: String

          # @rbs override
          def initialize(tree, source)
            @tree = tree
            @source = source

            @error_string = tree.nth_tree(1).to_s
          end
        end

        class Dot3Assertion < Base
          # @rbs override
          def initialize(tree, source)
            @tree = tree
            @source = source
          end
        end

        # `#[TYPE, ..., TYPE]`
        #
        class Application < Base
          attr_reader :types #: Array[Types::t]?

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
          attr_reader :contents #: Array[String]

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

          def annotations #: Array[RBS::AST::Annotation]
            contents.map do |content|
              RBS::AST::Annotation.new(string: content[3..-2] || raise, location: nil)
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
          attr_reader :super_name #: TypeName?
          attr_reader :args #: Array[Types::t]?

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
          attr_reader :clauses #: Array[RBS::AST::Directives::Use::clause]

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
          attr_reader :self_types #: Array[RBS::AST::Declarations::Module::Self]

          attr_reader :comment #: String?

          # @rbs override
          def initialize(tree, source)
            @tree = tree
            @source = source
            @self_types = []

            module_self = tree.nth_tree!(1)
            self_trees = module_self.non_trivia_trees
            self_trees.shift

            while true
              type = self_trees.shift
              case type
              when Types::ClassInstance, Types::Interface
                @self_types << RBS::AST::Declarations::Module::Self.new(
                  name: type.name,
                  args: type.args,
                  location: nil
                )
              end

              break if self_trees.empty?

              next_tree = self_trees.first
              if next_tree.is_a?(Array) && next_tree[0] == :kCOMMA
                self_trees.shift
              else
                break
              end
            end

            if comment = self_trees.first
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
          attr_reader :type_param #: RBS::AST::TypeParam?

          attr_reader :comment #: String?

          include Utils

          # @rbs override
          def initialize(tree, source)
            @tree = tree
            @source = source

            generic_tree = tree.nth_tree!(1)

            @type_param = translate_type_param(generic_tree.nth_tree!(1))

            if comment = generic_tree.nth_tree?(2)
              @comment = comment.to_s
            end
          end
        end

        # `# @rbs!` annotation
        class Embedded < Base
          attr_reader :content #: String

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
          # @rbs! type method_type = [MethodType, method_type?] | String

          attr_reader :method_types #: method_type?

          # `true` if the method definition is overloading something
          #
          attr_reader :overloading #: bool

          attr_reader :type #: MethodType?

          attr_reader :method_type_source #: String

          # @rbs override
          def initialize(tree, source)
            @tree = tree
            @source = source

            overloads = tree.nth_tree!(1)
            @method_types = construct_method_types(overloads.non_trivia_trees.dup)
            @overloading = overloads.token?(:kDOT3, at: -1)
          end

          #: (Array[tree]) -> method_type?
          def construct_method_types(children)
            first = children.shift

            case first
            when MethodType
              children.shift
              [
                first,
                construct_method_types(children)
              ]
            when Array
              # `...`
              nil
            when AST::Tree
              # Syntax error
              first.to_s
            end
          end

          # @rbs () { (MethodType) -> void } -> void
          #    | () -> Enumerator[MethodType, void]
          def each_method_type
            if block_given?
              type = self.method_types

              while true
                if type.is_a?(Array)
                  yield type[0]
                  type = type[1]
                else
                  break
                end
              end
            else
              enum_for :each_method_type
            end
          end

          # Returns the parsing error overload string
          #
          # Returns `nil` if no parsing error found.
          #
          def error_source #: String?
            type = self.method_types

            while true
              if type.is_a?(Array)
                type = type[1]
              else
                break
              end
            end

            if type.is_a?(String)
              type
            end
          end
        end

        # `@rbs module Foo`
        class ModuleDecl < Base
          attr_reader :name #: TypeName?

          attr_reader :type_params #: Array[RBS::AST::TypeParam]

          attr_reader :self_types #: Array[RBS::AST::Declarations::Module::Self]

          include Utils

          # @rbs override
          def initialize(tree, comments)
            @tree = tree
            @source = comments

            decl_tree = tree.nth_tree!(1)

            if type_name = translate_type_name(decl_tree.nth_tree!(1))
              if type_name.class?
                @name = type_name
              end
            end

            @type_params = []
            if type_params = decl_tree.nth_tree(2)
              params = type_params.non_trivia_trees
              params.shift
              params.pop
              params.each_slice(2) do |param, _comma|
                raise unless param.is_a?(Tree)
                if type_param = translate_type_param(param)
                  @type_params << type_param
                end
              end
            end

            @self_types = []
            if selfs_tree = decl_tree.nth_tree(3)
              self_trees = selfs_tree.non_trivia_trees
              self_trees.shift

              self_trees.each_slice(2) do |type, _comma|
                case type
                when Types::ClassInstance, Types::Interface
                  @self_types << RBS::AST::Declarations::Module::Self.new(
                    name: type.name,
                    args: type.args,
                    location: type.location
                  )
                end
              end
            end
          end
        end

        # `@rbs class Foo`
        class ClassDecl < Base
          attr_reader :name #: TypeName?

          attr_reader :type_params #: Array[RBS::AST::TypeParam]

          attr_reader :super_class #: RBS::AST::Declarations::Class::Super?

          include Utils

          # @rbs override
          def initialize(tree, comments)
            @tree = tree
            @source = comments

            decl_tree = tree.nth_tree!(1)

            if type_name = translate_type_name(decl_tree.nth_tree!(1))
              if type_name.class?
                @name = type_name
              end
            end

            @type_params = []
            if type_params = decl_tree.nth_tree(2)
              params = type_params.non_trivia_trees
              params.shift
              params.pop
              params.each_slice(2) do |param, _comma|
                raise unless param.is_a?(Tree)
                if type_param = translate_type_param(param)
                  @type_params << type_param
                end
              end
            end

            if super_tree = decl_tree.nth_tree(3)
              if type = super_tree.nth_type?(1)
                @super_class = translate_super_class(type)
              end
            end
          end
        end
      end
    end
  end
end
