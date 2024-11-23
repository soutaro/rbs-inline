# rbs_inline: enabled

module RBS
  module Inline
    module AST
      module Members
        # @rbs!
        #   type ruby = RubyDef | RubyAlias | RubyMixin | RubyAttr | RubyPublic | RubyPrivate
        #
        #   type rbs = RBSIvar | RBSEmbedded
        #
        #   type t = ruby | rbs

        class Base
          attr_reader :location #: Prism::Location

          # @rbs location: Prism::Location
          def initialize(location) #: void
            @location = location
          end

          def start_line #: Integer
            location.start_line
          end
        end

        class RubyBase < Base
        end

        class RubyDef < RubyBase
          attr_reader :node #: Prism::DefNode
          attr_reader :comments #: AnnotationParser::ParsingResult?

          # The visibility directly attached to the `def` node
          #
          # `nil` when the `def` node is not passed to `private`/`public` calls.
          #
          # ```rb
          # def foo() end            # <= nil
          # private def foo() end    # <= :private
          # ```
          attr_reader :visibility #: RBS::AST::Members::visibility?

          # The function is defined as singleton and instance method (as known as module_function)
          #
          attr_accessor :singleton_instance #: bool

          # Assertion given at the end of the method name
          #
          attr_reader :assertion #: Annotations::TypeAssertion?

          # @rbs node: Prism::DefNode
          # @rbs comments: AnnotationParser::ParsingResult?
          # @rbs visibility: RBS::AST::Members::visibility?
          # @rbs singleton_instance: bool
          # @rbs assertion: Annotations::TypeAssertion?
          def initialize(node, comments, visibility, singleton_instance, assertion) #: void
            @node = node
            @comments = comments
            @visibility = visibility
            @singleton_instance = singleton_instance
            @assertion = assertion

            super(node.location)
          end

          # Returns the name of the method
          def method_name #: Symbol
            node.name
          end

          # Returns `nil` if no `@rbs METHOD-TYPE` or `#:` annotation is given
          #
          # Returns an empty array if only `...` method type is given.
          #
          def annotated_method_types #: Array[MethodType]?
            if comments
              method_type_annotations = comments.each_annotation.select do |annotation|
                annotation.is_a?(Annotations::MethodTypeAssertion) || annotation.is_a?(Annotations::Method) || annotation.is_a?(Annotations::Dot3Assertion)
              end

              return nil if method_type_annotations.empty?

              method_type_annotations.each_with_object([]) do |annotation, method_types| #$ Array[MethodType]
                case annotation
                when Annotations::MethodTypeAssertion
                  method_types << annotation.method_type
                when Annotations::Method
                  annotation.each_method_type do
                    method_types << _1
                  end
                end
              end
            end
          end

          def return_type #: Types::t?
            if assertion
              return assertion.type
            end

            if comments
              annot = comments.each_annotation.find {|annot| annot.is_a?(Annotations::ReturnType ) } #: Annotations::ReturnType?
              if annot
                annot.type
              end
            end
          end

          def var_type_hash #: Hash[Symbol, Types::t?]
            types = {} #: Hash[Symbol, Types::t?]

            if comments
              comments.each_annotation.each do |annotation|
                if annotation.is_a?(Annotations::VarType)
                  name = annotation.name
                  type = annotation.type

                  if name
                    types[name] = type
                  end
                end
              end
            end

            types
          end

          def splat_param_type_annotation #: Annotations::SplatParamType?
            if comments
              comments.each_annotation.find do |annotation|
                annotation.is_a?(Annotations::SplatParamType)
              end #: Annotations::SplatParamType?
            end
          end

          def double_splat_param_type_annotation #: Annotations::DoubleSplatParamType?
            if comments
              comments.each_annotation.find do |annotation|
                annotation.is_a?(Annotations::DoubleSplatParamType)
              end #: Annotations::DoubleSplatParamType?
            end
          end

          def overloading? #: bool
            if comments
              comments.each_annotation do |annotation|
                if annotation.is_a?(Annotations::Method)
                  return true if annotation.overloading
                end
                if annotation.is_a?(Annotations::Dot3Assertion)
                  return true
                end
              end
              false
            else
              false
            end
          end

          def method_overloads #: Array[RBS::AST::Members::MethodDefinition::Overload]
            case
            when method_types = annotated_method_types
              method_types.map do |method_type|
                RBS::AST::Members::MethodDefinition::Overload.new(
                  method_type: method_type,
                  annotations: []
                )
              end
            else
              required_positionals = [] #: Array[Types::Function::Param]
              optional_positionals = [] #: Array[Types::Function::Param]
              rest_positionals = nil #: Types::Function::Param?
              required_keywords = {} #: Hash[Symbol, Types::Function::Param]
              optional_keywords = {} #: Hash[Symbol, Types::Function::Param]
              rest_keywords = nil #: Types::Function::Param?
              forwarding_parameter = false

              if node.parameters
                node.parameters.requireds.each do |param|
                  case param
                  when Prism::RequiredParameterNode
                    required_positionals << Types::Function::Param.new(
                      name: param.name,
                      type: var_type_hash[param.name] || Types::Bases::Any.new(location: nil),
                      location: nil
                    )
                  end
                end

                node.parameters.optionals.each do |param|
                  case param
                  when Prism::OptionalParameterNode
                    optional_positionals << Types::Function::Param.new(
                      name: param.name,
                      type: var_type_hash[param.name] || Types::Bases::Any.new(location: nil),
                      location: nil
                    )
                  end
                end

                if (rest = node.parameters.rest).is_a?(Prism::RestParameterNode)
                  splat_param_type = splat_param_type_annotation

                  if splat_param_type && splat_param_type.type
                    splat_type = splat_param_type.type
                  end

                  rest_positionals = Types::Function::Param.new(
                    name: rest.name,
                    type: splat_type || Types::Bases::Any.new(location: nil),
                    location: nil
                  )
                end

                node.parameters.keywords.each do |node|
                  if node.is_a?(Prism::RequiredKeywordParameterNode)
                    required_keywords[node.name] = Types::Function::Param.new(
                      name: nil,
                      type: var_type_hash[node.name] || Types::Bases::Any.new(location: nil),
                      location: nil
                    )
                  end

                  if node.is_a?(Prism::OptionalKeywordParameterNode)
                    optional_keywords[node.name] = Types::Function::Param.new(
                      name: nil,
                      type: var_type_hash[node.name] || Types::Bases::Any.new(location: nil),
                      location: nil
                    )
                  end
                end

                case node.parameters.keyword_rest
                when Prism::KeywordRestParameterNode
                  double_splat_param_type = double_splat_param_type_annotation

                  if double_splat_param_type && double_splat_param_type.type
                    double_splat_type = double_splat_param_type.type
                  end

                  rest_keywords = Types::Function::Param.new(
                    name: node.parameters.keyword_rest.name,
                    type: double_splat_type || Types::Bases::Any.new(location: nil),
                    location: nil)
                when Prism::ForwardingParameterNode
                  forwarding_parameter = true
                end

                if node.parameters.block
                  block = Types::Block.new(
                    type: Types::UntypedFunction.new(return_type: Types::Bases::Any.new(location: nil)),
                    required: false,
                    self_type: nil
                  )
                end
              end

              if type = block_type_annotation&.type
                block = type
              end

              if forwarding_parameter
                [
                  RBS::AST::Members::MethodDefinition::Overload.new(
                    method_type: RBS::MethodType.new(
                      type_params: [],
                      type: Types::UntypedFunction.new(return_type: return_type || Types::Bases::Any.new(location: nil)),
                      block: nil,
                      location: nil
                    ),
                    annotations: []
                  )
                ]
              else
                [
                  RBS::AST::Members::MethodDefinition::Overload.new(
                    method_type: RBS::MethodType.new(
                      type_params: [],
                      type: Types::Function.new(
                        required_positionals: required_positionals,
                        optional_positionals: optional_positionals,
                        rest_positionals: rest_positionals,
                        trailing_positionals: [],
                        required_keywords: required_keywords,
                        optional_keywords: optional_keywords,
                        rest_keywords: rest_keywords,
                        return_type: return_type || Types::Bases::Any.new(location: nil)
                      ),
                      block: block,
                      location: nil
                    ),
                    annotations: []
                  )
                ]
              end
            end
          end

          def method_annotations #: Array[RBS::AST::Annotation]
            if comments
              comments.each_annotation.flat_map do |annotation|
                if annotation.is_a?(AST::Annotations::RBSAnnotation)
                  annotation.annotations
                else
                  []
                end
              end
            else
              []
            end
          end

          # Returns the `@rbs override` annotation
          def override_annotation #: AST::Annotations::Override?
            if comments
              comments.each_annotation.find do |annotation|
                annotation.is_a?(AST::Annotations::Override)
              end #: AST::Annotations::Override?
            end
          end

          def block_type_annotation #: AST::Annotations::BlockType?
            if comments
              comments.each_annotation.find do |annotation|
                annotation.is_a?(AST::Annotations::BlockType)
              end #: AST::Annotations::BlockType?
            end
          end
        end

        class RubyAlias < RubyBase
          attr_reader :node #: Prism::AliasMethodNode
          attr_reader :comments #: AnnotationParser::ParsingResult?

          # @rbs node: Prism::AliasMethodNode
          # @rbs comments: AnnotationParser::ParsingResult?
          def initialize(node, comments) #: void
            @node = node
            @comments = comments

            super(node.location)
          end

          # @rbs return: Symbol -- the name of *old* method
          def old_name
            raise unless node.old_name.is_a?(Prism::SymbolNode)
            value = node.old_name.value or raise
            value.to_sym
          end

          # @rbs return: Symbol -- the name of *new* method
          def new_name
            raise unless node.new_name.is_a?(Prism::SymbolNode)
            value = node.new_name.value or raise
            value.to_sym
          end
        end

        class RubyMixin < RubyBase
          include Declarations::ConstantUtil

          # CallNode that calls `include`, `prepend`, and `extend` method
          attr_reader :node #: Prism::CallNode

          # Comments attached to the call node
          attr_reader :comments #: AnnotationParser::ParsingResult?

          # Possible following type application annotation
          attr_reader :application #: Annotations::Application?

          # @rbs node: Prism::CallNode
          # @rbs comments: AnnotationParser::ParsingResult?
          # @rbs application: Annotations::Application?
          # @rbs return: void
          def initialize(node, comments, application)
            super(node.location)

            @node = node
            @comments = comments
            @application = application
          end

          # @rbs return: ::RBS::AST::Members::Include
          #            | ::RBS::AST::Members::Extend
          #            | ::RBS::AST::Members::Prepend
          #            | nil
          def rbs
            return unless node.arguments
            return unless node.arguments.arguments.size == 1

            arg = node.arguments.arguments[0] || raise
            type_name = type_name(arg)
            return unless type_name

            args = [] #: Array[Types::t]
            if application
              if application.types
                args.concat(application.types)
              end
            end

            case node.name
            when :include
              RBS::AST::Members::Include.new(
                name: type_name,
                args: args,
                annotations: [],
                location: nil,
                comment: nil
              )
            when :extend
              RBS::AST::Members::Extend.new(
                name: type_name,
                args: args,
                annotations: [],
                location: nil,
                comment: nil
              )
            when :prepend
              RBS::AST::Members::Prepend.new(
                name: type_name,
                args: args,
                annotations: [],
                location: nil,
                comment: nil
              )
            end
          end
        end

        class RubyAttr < RubyBase
          attr_reader :node #: Prism::CallNode
          attr_reader :comments #: AnnotationParser::ParsingResult?
          attr_reader :assertion #: Annotations::TypeAssertion?

          # @rbs node: Prism::CallNode
          # @rbs comments: AnnotationParser::ParsingResult?
          # @rbs assertion: Annotations::TypeAssertion?
          # @rbs return: void
          def initialize(node, comments, assertion)
            super(node.location)

            @node = node
            @comments = comments
            @assertion = assertion
          end

          # @rbs return Array[RBS::AST::Members::AttrReader | RBS::AST::Members::AttrWriter | RBS::AST::Members::AttrAccessor]?
          def rbs
            if comments
              comment = RBS::AST::Comment.new(string: comments.content(trim: true), location: nil)
            end

            klass =
              case node.name
              when :attr_reader
                RBS::AST::Members::AttrReader
              when :attr_writer
                RBS::AST::Members::AttrWriter
              when :attr_accessor
                RBS::AST::Members::AttrAccessor
              else
                raise
              end

            args = [] #: Array[Symbol]
            if node.arguments
              node.arguments.arguments.each do |arg|
                if arg.is_a?(Prism::SymbolNode)
                  value = arg.value or raise
                  args << value.to_sym
                end
              end
            end

            unless args.empty?
              args.map do |arg|
                klass.new(
                  name: arg,
                  type: attribute_type,
                  ivar_name: nil,
                  kind: :instance,
                  annotations: [],
                  location: nil,
                  comment: comment,
                  visibility: nil
                )
              end
            end
          end

          # Returns the type of the attribute
          #
          # Returns `untyped` when not annotated.
          #
          def attribute_type #: Types::t
            type = assertion&.type
            raise if type.is_a?(MethodType)

            type || Types::Bases::Any.new(location: nil)
          end
        end

        # `private` call without arguments
        #
        class RubyPrivate < RubyBase
          attr_reader :node #: Prism::CallNode

          # @rbs node: Prism::CallNode
          def initialize(node) #: void
            super(node.location)
            @node = node
          end
        end

        # `public` call without arguments
        #
        class RubyPublic < RubyBase
          attr_reader :node #: Prism::CallNode

          # @rbs node: Prism::CallNode
          def initialize(node) #: void
            super(node.location)
            @node = node
          end
        end

        class RBSBase < Base
        end

        class RBSIvar < RBSBase
          attr_reader :annotation #: Annotations::IvarType

          attr_reader :comment #: AnnotationParser::ParsingResult

          # @rbs comment: AnnotationParser::ParsingResult
          # @rbs annotation: Annotations::IvarType
          def initialize(comment, annotation) #: void
            @comment = comment
            @annotation = annotation

            super(comment.comments[0].location)
          end

          def rbs #: RBS::AST::Members::InstanceVariable | RBS::AST::Members::ClassInstanceVariable | nil
            if annotation.type
              if annotation.comment
                string = annotation.comment.delete_prefix("--").lstrip
                comment = RBS::AST::Comment.new(string: string, location: nil)
              end

              if annotation.class_instance
                RBS::AST::Members::ClassInstanceVariable.new(
                  name: annotation.name,
                  type: annotation.type,
                  location: nil,
                  comment: comment
                )
              else
                RBS::AST::Members::InstanceVariable.new(
                  name: annotation.name,
                  type: annotation.type,
                  location: nil,
                  comment: comment
                )
              end
            end
          end
        end

        class RBSEmbedded < RBSBase
          attr_reader :annotation #: Annotations::Embedded

          attr_reader :comment #: AnnotationParser::ParsingResult

          # @rbs comment: AnnotationParser::ParsingResult
          # @rbs annotation: Annotations::Embedded
          def initialize(comment, annotation) #: void
            @comment = comment
            @annotation = annotation

            super(comment.comments[0].location)
          end

          # Returns the array of `RBS::AST` members
          #
          # Returns `RBS::ParsingError` when the `content` has syntax error.
          #
          def members #: Array[RBS::AST::Members::t | RBS::AST::Declarations::t] | RBS::ParsingError
            source = <<~RBS
              module EmbeddedModuleTest
                #{annotation.content}
              end
            RBS

            _, _, decls = RBS::Parser.parse_signature(source)

            mod = decls[0]
            mod.is_a?(RBS::AST::Declarations::Module) or raise

            mod.members.each do |member|
              # Clear `@location` of each member so that new lines are inserted between members.
              # See `RBS::Writer#preserve_empty_line`.
              member.instance_variable_set(:@location, nil)
            end

          rescue RBS::ParsingError => exn
            exn
          end
        end
      end
    end
  end
end
