module RBS
  module Inline
    module AST
      module Members
        class Base

        end

        class RubyDef < Base
          attr_reader :node
          attr_reader :comments

          def initialize(node, comments)
            @node = node
            @comments = comments
          end

          def method_name
            node.name
          end

          def method_type_annotations
            if comments
              comments.annotations.select do |annotation|
                annotation.is_a?(Annotations::Assertion) && annotation.type.is_a?(MethodType)
              end #: Array[Annotations::Assertion]
            else
              []
            end
          end

          def return_type
            if comments
              annot = comments.annotations.find {|annot| annot.is_a?(Annotations::ReturnType ) } #: Annotations::ReturnType?
              if annot
                annot.type
              end
            end
          end

          def var_type_hash
            types = {} #: Hash[Symbol, Types::t?]

            if comments
              comments.annotations.each do |annotation|
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

          def method_overloads
            if !(annots = method_type_annotations).empty?
              annots.map do
                method_type = _1.type #: MethodType

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
                  rest_type =
                    if rest.name
                      var_type_hash[rest.name]
                    end

                  if rest_type
                    if rest_type.is_a?(Types::ClassInstance)
                      if rest_type.name.name == :Array && rest_type.name.namespace.empty?
                        rest_type = rest_type.args[0]
                      end
                    end
                  end

                  rest_positionals = Types::Function::Param.new(
                    name: rest.name,
                    type: rest_type || Types::Bases::Any.new(location: nil),
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

                if (kw_rest = node.parameters.keyword_rest).is_a?(Prism::KeywordRestParameterNode)
                  rest_type =
                    if kw_rest.name
                      var_type_hash[kw_rest.name]
                    end

                  if rest_type
                    if rest_type.is_a?(Types::ClassInstance)
                      if rest_type.name.name == :Hash && rest_type.name.namespace.empty?
                        rest_type = rest_type.args[1]
                      end
                    end
                  end

                  rest_keywords = Types::Function::Param.new(
                    name: kw_rest.name,
                    type: rest_type || Types::Bases::Any.new(location: nil),
                    location: nil)
                end
              end

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
                    block: nil,
                    location: nil
                  ),
                  annotations: []
                )
              ]
            end
          end

          def method_annotations
            if comments
              comments.annotations.flat_map do |annotation|
                if annotation.is_a?(AST::Annotations::RBSAnnotation)
                  annotation.contents.map do |string|
                    RBS::AST::Annotation.new(
                      string: string[3...-1] || "",
                      location: nil
                    )
                  end
                else
                  []
                end
              end
            else
              []
            end
          end
        end

        class RubyAlias < Base
          attr_reader :node, :comments

          def initialize(node, comments)
            @node = node
            @comments = comments
          end

          def old_name
            raise unless node.old_name.is_a?(Prism::SymbolNode)
            value = node.old_name.value or raise
            value.to_sym
          end

          def new_name
            raise unless node.new_name.is_a?(Prism::SymbolNode)
            value = node.new_name.value or raise
            value.to_sym
          end
        end

        class RubyMixin < Base
          attr_reader :node, :comments, :application

          def initialize(node, comments, application)
            @node = node
            @comments = comments
            @application = application
          end

          def mixin_member
            args = node.arguments
          end
        end
      end
    end
  end
end
