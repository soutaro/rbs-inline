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
            when Prism::ConstantReadNode
              TypeName(node.name.to_s)
            when Prism::ConstantPathNode
              if node.parent
                if parent = type_name(node.parent)
                  if child = type_name(node.child)
                    return parent + child
                  end
                end
              else
                type_name(node.child)&.absolute!
              end
            end
          end
        end

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

        class ClassDecl < Base
          include ConstantUtil
          include Generics

          attr_reader :node #:: Prism::ClassNode
          attr_reader :comments #:: AnnotationParser::ParsingResult?
          attr_reader :members #:: Array[Members::t | t]
          attr_reader :super_application #:: Annotations::Application?

          # @rbs node: Prism::ClassNode
          # @rbs comments: AnnotationParser::ParsingResult?
          # @rbs super_app: Annotations::Application?
          # @rbs returns void
          def initialize(node, comments, super_app)
            @node = node
            @members = []
            @comments = comments
            @super_application = super_app
          end

          # @rbs %a{pure}
          # @rbs returns TypeName?
          def class_name
            type_name(node.constant_path)
          end

          # @rbs %a{pure}
          # @rbs returns RBS::AST::Declarations::Class::Super?
          def super_class
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

              if super_application
                super_args = super_application.types
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

        class ModuleDecl < Base
          include ConstantUtil
          include Generics

          attr_reader :node #:: Prism::ModuleNode
          attr_reader :members #:: Array[Members::t | t]
          attr_reader :comments #:: AnnotationParser::ParsingResult?
          attr_reader :inner_comments #:: Array[AnnotationParser::ParsingResult]

          # @rbs node: Prism::ModuleNode
          # @rbs comments: AnnotationParser::ParsingResult?
          # @rbs returns void
          def initialize(node, comments)
            @node = node
            @comments = comments
            @members = []
            @inner_comments = []
          end

          # @rbs %a{pure}
          # @rbs returns TypeName?
          def module_name
            type_name(node.constant_path)
          end

          # @rbs %a{pure}
          # @rbs returns Array[Annotations::ModuleSelf]
          def module_selfs
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
        end
      end
    end
  end
end
