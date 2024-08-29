# rbs_inline: enabled

module RBS
  module Inline
    module AST
      module Declarations
        module ConstantUtil
          # @rbs node: Prism::Node
          # @rbs return: TypeName?
          def type_name(node)
            case node
            when Prism::ConstantReadNode, Prism::ConstantPathNode
              TypeName(node.full_name)
            end
          end

          # @rbs (Prism::Node) -> Prism::Node?
          def value_node(node)
            case node
            when Prism::ConstantWriteNode
              value_node(node.value)
            when Prism::LocalVariableWriteNode
              value_node(node.value)
            else
              node
            end
          end
        end

        # @rbs!
        #   type t = ClassDecl | ModuleDecl | ConstantDecl | SingletonClassDecl | BlockDecl | DataAssignDecl | StructAssignDecl
        #
        #  interface _WithComments
        #    def comments: () -> AnnotationParser::ParsingResult?
        #  end

        # @rbs module-self _WithComments
        module Generics
          # @rbs return: Array[RBS::AST::TypeParam]
          def type_params
            if comments = comments()
              comments.each_annotation.filter_map do |annotation|
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
          attr_reader :node #: NODE

          # Leading comment
          attr_reader :comments #: AnnotationParser::ParsingResult?

          # Members included in the declaration
          attr_reader :members #: Array[Members::t | t]

          # @rbs node: NODE
          # @rbs comments: AnnotationParser::ParsingResult?
          def initialize(node, comments) #: void
            @node = node
            @comments = comments
            @members = []
          end

          # Type parameters for the declaration
          def type_params #: Array[RBS::AST::TypeParam]
            if comments = comments()
              comments.each_annotation.filter_map do |annotation|
                if annotation.is_a?(Annotations::Generic)
                  annotation.type_param
                end
              end
            else
              []
            end
          end

          def start_line #: Integer
            node.location.start_line
          end
        end

        class ClassDecl < ModuleOrClass #[Prism::ClassNode]
          include ConstantUtil

          # Type application for super class
          attr_reader :super_app #: Annotations::Application?

          # @rbs node: Prism::ClassNode
          # @rbs comments: AnnotationParser::ParsingResult?
          # @rbs super_app: Annotations::Application?
          # @rbs return: void
          def initialize(node, comments, super_app)
            super(node, comments)

            @super_app = super_app
          end

          # @rbs %a{pure}
          def class_name #: TypeName?
            type_name(node.constant_path)
          end

          # @rbs %a{pure}
          def super_class #: RBS::AST::Declarations::Class::Super?
            if comments
              if inherits = comments.each_annotation.find {|a| a.is_a?(Annotations::Inherits) } #: Annotations::Inherits?
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
          def module_name #: TypeName?
            type_name(node.constant_path)
          end

          # @rbs %a{pure}
          def module_selfs #: Array[Annotations::ModuleSelf]
            if comments
              comments.each_annotation.filter_map do |ann|
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

          attr_reader :node #: Prism::ConstantWriteNode
          attr_reader :comments #: AnnotationParser::ParsingResult?
          attr_reader :assertion #: Annotations::TypeAssertion?

          # @rbs node: Prism::ConstantWriteNode
          # @rbs comments: AnnotationParser::ParsingResult?
          # @rbs assertion: Annotations::TypeAssertion?
          def initialize(node, comments, assertion) #: void
            @node = node
            @comments = comments
            @assertion = assertion
          end

          # @rbs %a{pure}
          # @rbs return: Types::t
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
          # @rbs return: TypeName?
          def constant_name
            TypeName.new(name: node.name, namespace: Namespace.empty)
          end

          def start_line #: Integer
            node.location.start_line
          end
        end

        class SingletonClassDecl < ModuleOrClass #[Prism::SingletonClassNode]
          # @rbs (AST::Members::RubyDef) -> (:private | nil)
          def visibility(def_member)
            current_visibility = nil
            members.each do |member|
              case member
              when AST::Members::RubyPublic
                current_visibility = nil
              when AST::Members::RubyPrivate
                current_visibility = :private
              end

              break if member == def_member
            end
            current_visibility
          end
        end

        class BlockDecl < Base
          attr_reader :node #: Prism::BlockNode

          attr_reader :comments #: AnnotationParser::ParsingResult?

          # Members included in the declaration
          attr_reader :members #: Array[Members::t | t]

          # @rbs (Prism::BlockNode, AnnotationParser::ParsingResult?) -> void
          def initialize(node, comments)
            @node = node
            @members = []
            @comments = comments
          end

          def start_line #: Integer
            node.location.start_line
          end

          def module_class_annotation #: Annotations::ModuleDecl | Annotations::ClassDecl | nil
            if comments
              comments.each_annotation.each do |annotation|
                if annotation.is_a?(Annotations::ModuleDecl)
                  return annotation
                end

                if annotation.is_a?(Annotations::ClassDecl)
                  return annotation
                end
              end

              nil
            end
          end
        end

        # @rbs module-self _WithTypeDecls
        module DataStructUtil
          # @rbs!
          #   interface _WithTypeDecls
          #     def type_decls: () -> Hash[Integer, Annotations::TypeAssertion]
          #
          #     def each_attribute_argument: () { (Prism::Node) -> void } -> void
          #
          #     def comments: %a{pure} () -> AnnotationParser::ParsingResult?
          #   end

          # @rbs %a{pure}
          # @rbs () { ([Symbol, Annotations::TypeAssertion?]) -> void } -> void
          #    | () -> Enumerator[[Symbol, Annotations::TypeAssertion?], void]
          def each_attribute(&block)
            if block
              each_attribute_argument do |arg|
                if arg.is_a?(Prism::SymbolNode)
                  if name = arg.value
                    type = type_decls.fetch(arg.location.start_line, nil)
                    yield [name.to_sym, type]
                  end
                end
              end
            else
              enum_for :each_attribute
            end
          end

          def class_annotations #: Array[RBS::AST::Annotation]
            annotations = [] #: Array[RBS::AST::Annotation]

            comments&.each_annotation do |annotation|
              if annotation.is_a?(Annotations::RBSAnnotation)
                annotations.concat annotation.annotations
              end
            end

            annotations
          end
        end

        class DataAssignDecl < Base
          extend ConstantUtil

          include DataStructUtil

          attr_reader :node #: Prism::ConstantWriteNode

          attr_reader :comments #: AnnotationParser::ParsingResult?

          attr_reader :type_decls #: Hash[Integer, Annotations::TypeAssertion]

          attr_reader :data_define_node #: Prism::CallNode

          # @rbs (Prism::ConstantWriteNode, Prism::CallNode, AnnotationParser::ParsingResult?, Hash[Integer, Annotations::TypeAssertion]) -> void
          def initialize(node, data_define_node, comments, type_decls)
            @node = node
            @comments = comments
            @type_decls = type_decls
            @data_define_node = data_define_node
          end

          def start_line #: Integer
            node.location.start_line
          end

          # @rbs %a{pure}
          # @rbs () -> TypeName?
          def constant_name
            TypeName.new(name: node.name, namespace: Namespace.empty)
          end

          # @rbs (Prism::ConstantWriteNode) -> Prism::CallNode?
          def self.data_define?(node)
            value = value_node(node)

            if value.is_a?(Prism::CallNode)
              if value.receiver.is_a?(Prism::ConstantReadNode)
                if value.receiver.full_name.delete_prefix("::") == "Data"
                  if value.name == :define
                    return value
                  end
                end
              end
            end
          end

          # @rbs () { (Prism::Node) -> void } -> void
          def each_attribute_argument(&block)
            if args = data_define_node.arguments
              args.arguments.each(&block)
            end
          end
        end

        class StructAssignDecl < Base
          extend ConstantUtil

          include DataStructUtil

          attr_reader :node #: Prism::ConstantWriteNode

          attr_reader :comments #: AnnotationParser::ParsingResult?

          attr_reader :type_decls #: Hash[Integer, Annotations::TypeAssertion]

          attr_reader :struct_new_node #: Prism::CallNode

          # @rbs (Prism::ConstantWriteNode, Prism::CallNode, AnnotationParser::ParsingResult?, Hash[Integer, Annotations::TypeAssertion]) -> void
          def initialize(node, struct_new_node, comments, type_decls)
            @node = node
            @comments = comments
            @type_decls = type_decls
            @struct_new_node = struct_new_node
          end

          def start_line #: Integer
            node.location.start_line
          end

          # @rbs %a{pure}
          # @rbs () -> TypeName?
          def constant_name
            TypeName.new(name: node.name, namespace: Namespace.empty)
          end

          # @rbs () { (Prism::Node) -> void } -> void
          def each_attribute_argument(&block)
            if args = struct_new_node.arguments
              args.arguments.each do |arg|
                next if arg.is_a?(Prism::KeywordHashNode)
                next if arg.is_a?(Prism::StringNode)

                yield arg
              end
            end
          end

          # @rbs (Prism::ConstantWriteNode) -> Prism::CallNode?
          def self.struct_new?(node)
            value = value_node(node)

            if value.is_a?(Prism::CallNode)
              if value.receiver.is_a?(Prism::ConstantReadNode)
                if value.receiver.full_name.delete_prefix("::") == "Struct"
                  if value.name == :new
                    return value
                  end
                end
              end
            end
          end

          # @rbs %a{pure}
          def keyword_init? #: bool
            if args = struct_new_node.arguments
              args.arguments.each do |arg|
                if arg.is_a?(Prism::KeywordHashNode)
                  arg.elements.each do |assoc|
                    if assoc.is_a?(Prism::AssocNode)
                      if (key = assoc.key).is_a?(Prism::SymbolNode)
                        if key.value == "keyword_init"
                          value = assoc.value
                          if value.is_a?(Prism::FalseNode)
                            return false
                          end
                        end
                      end
                    end
                  end
                end
              end
            end

            true
          end

          # @rbs %a{pure}
          def positional_init? #: bool
            if args = struct_new_node.arguments
              args.arguments.each do |arg|
                if arg.is_a?(Prism::KeywordHashNode)
                  arg.elements.each do |assoc|
                    if assoc.is_a?(Prism::AssocNode)
                      if (key = assoc.key).is_a?(Prism::SymbolNode)
                        if key.value == "keyword_init"
                          value = assoc.value
                          if value.is_a?(Prism::TrueNode)
                            return false
                          end
                        end
                      end
                    end
                  end
                end
              end
            end

            true
          end

          # Returns `true` is annotation is given to make all attributes *readonly*
          #
          # Add `# @rbs %a{rbs-inline:readonly-attributes=true}` to the class to make all attributes `attr_reader`, instead of `attr_accessor`.
          #
          # @rbs %a{pure}
          def readonly_attributes? #: bool
            class_annotations.any? do |annotation|
              annotation.string == "rbs-inline:readonly-attributes=true"
            end
          end

          # Returns `true` if annotation is given to make all `.new` arguments required
          #
          # Add `# @rbs %a{rbs-inline:new-args=required}` to the class to make all of the parameters required.
          #
          # @rbs %a{pure}
          def required_new_args? #: bool
            class_annotations.any? do |annotation|
              annotation.string == "rbs-inline:new-args=required"
            end
          end
        end
      end
    end
  end
end
