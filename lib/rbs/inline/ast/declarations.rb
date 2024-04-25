module RBS
  module Inline
    module AST
      module Declarations
        module ConstantUtil
          def type_name(node)
            case node
            when Prism::ConstantReadNode
              TypeName(node.name.to_s)
            end
          end
        end

        class Base
        end

        class ClassDecl < Base
          include ConstantUtil

          attr_reader :node
          attr_reader :comments
          attr_reader :members
          attr_reader :super_application

          def initialize(node, comments, super_app)
            @node = node
            @members = []
            @comments = comments
            @super_application = super_app
          end

          def class_name
            type_name(node.constant_path)
          end

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

          attr_reader :node
          attr_reader :members
          attr_reader :comments
          attr_reader :inner_comments

          def initialize(node, comments)
            @node = node
            @comments = comments
            @members = []
            @inner_comments = []
          end

          def module_name
            type_name(node.constant_path)
          end

          def module_selfs
            inner_comments.flat_map do |comment|
              comment.annotations.filter_map do |ann|
                if ann.is_a?(AST::Annotations::ModuleSelf)
                  ann
                end
              end
            end
          end
        end
      end
    end
  end
end
