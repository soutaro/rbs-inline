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

          def initialize(node, comments)
            @node = node
            @members = []
            @comments = comments
          end

          def class_name
            type_name(node.constant_path)
          end

          def super_class
            if node.superclass
              type_name(node.superclass)
            end
          end
        end
      end
    end
  end
end
