# rbs_inline: enabled

module RBS
  module Inline
    module AST
      module Declarations
        module ConstantUtil
          # @rbs node: Prism::Node
          # @rbs returns TypeName?
          def type_name(node)
            case node
            when Prism::ConstantReadNode, Prism::ConstantPathNode
              TypeName(node.full_name)
            end
          end
        end

        # @rbs! type t = ClassDecl | ModuleDecl | ConstantDecl | SingletonClassDecl

        # @rbs!
        #  interface _WithComments
        #    def comments: () -> AnnotationParser::ParsingResult?
        #  end

        # @rbs module-self _WithComments
        module Generics
          # @rbs returns Array[RBS::AST::TypeParam]
          def type_params
            if comments = comments()
              comments.annotations.filter_map do |annotation|
                if annotation.is_a?(Annotations::Generic)
                  annotation.type_param
                end
              end
            else
              []
            end
          end
        end

        class Base
        end

        # @rbs generic NODE < Prism::Node
        class ModuleOrClass < Base
          # The node that represents the declaration
          attr_reader :node #:: NODE

          # Leading comment
          attr_reader :comments #:: AnnotationParser::ParsingResult?

          # Members included in the declaration
          attr_reader :members #:: Array[Members::t | t]

          # @rbs node: NODE
          # @rbs comments: AnnotationParser::ParsingResult?
          def initialize(node, comments) #:: void
            @node = node
            @comments = comments
            @members = []
          end

          # Type parameters for the declaration
          def type_params #:: Array[RBS::AST::TypeParam]
            if comments = comments()
              comments.annotations.filter_map do |annotation|
                if annotation.is_a?(Annotations::Generic)
                  annotation.type_param
                end
              end
            else
              []
            end
          end

          def start_line #:: Integer
            node.location.start_line
          end
        end

        class ClassDecl < ModuleOrClass #[Prism::ClassNode]
          include ConstantUtil

          # Type application for super class
          attr_reader :super_app #:: Annotations::Application?

          # @rbs node: Prism::ClassNode
          # @rbs comments: AnnotationParser::ParsingResult?
          # @rbs super_app: Annotations::Application?
          # @rbs returns void
          def initialize(node, comments, super_app)
            super(node, comments)

            @super_app = super_app
          end

          # @rbs %a{pure}
          def class_name #:: TypeName?
            type_name(node.constant_path)
          end

          # @rbs %a{pure}
          def super_class #:: RBS::AST::Declarations::Class::Super?
            if comments
              if inherits = comments.annotations.find {|a| a.is_a?(Annotations::Inherits) } #: Annotations::Inherits?
                super_name = inherits.super_name
                super_args = inherits.args

                if super_name && super_args
                  return RBS::AST::Declarations::Class::Super.new(
                    name: super_name,
                    args: super_args,
                    location: nil
                  )
                end
              end
            end

            if node.superclass
              super_name = nil #: TypeName?
              super_args = nil #: Array[Types::t]?

              if super_app
                super_args = super_app.types
              end

              super_name = type_name(node.superclass)

              if super_name
                return RBS::AST::Declarations::Class::Super.new(
                  name: super_name,
                  args: super_args || [],
                  location: nil
                )
              end
            end
          end
        end

        class ModuleDecl  < ModuleOrClass #[Prism::ModuleNode]
          include ConstantUtil

          # @rbs %a{pure}
          def module_name #:: TypeName?
            type_name(node.constant_path)
          end

          # @rbs %a{pure}
          def module_selfs #:: Array[Annotations::ModuleSelf]
            if comments
              comments.annotations.filter_map do |ann|
                if ann.is_a?(AST::Annotations::ModuleSelf)
                  ann
                end
              end
            else
              []
            end
          end
        end

        class ConstantDecl < Base
          include ConstantUtil

          attr_reader :node #:: Prism::ConstantWriteNode
          attr_reader :comments #:: AnnotationParser::ParsingResult?
          attr_reader :assertion #:: Annotations::Assertion?

          # @rbs node: Prism::ConstantWriteNode
          # @rbs comments: AnnotationParser::ParsingResult?
          # @rbs assertion: Annotations::Assertion?
          def initialize(node, comments, assertion)
            @node = node
            @comments = comments
            @assertion = assertion
          end

          # @rbs %a{pure}
          # @rbs returns Types::t
          def type
            if assertion
              case assertion.type
              when MethodType, nil
                # skip
              else
                return assertion.type
              end
            end

            if literal = literal_type
              return literal
            end

            Types::Bases::Any.new(location: nil)
          end

          # @rbs %a{pure}
          # @rbs return Types::t?
          def literal_type
            case node.value
            when Prism::StringNode, Prism::InterpolatedStringNode
              BuiltinNames::String.instance_type
            when Prism::SymbolNode, Prism::InterpolatedSymbolNode
              BuiltinNames::Symbol.instance_type
            when Prism::RegularExpressionNode, Prism::InterpolatedRegularExpressionNode
              BuiltinNames::Regexp.instance_type
            when Prism::IntegerNode
              BuiltinNames::Integer.instance_type
            when Prism::FloatNode
              BuiltinNames::Float.instance_type
            when Prism::ArrayNode
              BuiltinNames::Array.instance_type
            when Prism::HashNode
              BuiltinNames::Hash.instance_type
            when Prism::TrueNode, Prism::FalseNode
              Types::Bases::Bool.new(location: nil)
            end
          end

          # @rbs %a{pure}
          # @rbs returns TypeName?
          def constant_name
            TypeName.new(name: node.name, namespace: Namespace.empty)
          end

          def start_line #:: Integer
            node.location.start_line
          end
        end

        class SingletonClassDecl < ModuleOrClass #[Prism::SingletonClassNode]
        end
      end
    end
  end
end
