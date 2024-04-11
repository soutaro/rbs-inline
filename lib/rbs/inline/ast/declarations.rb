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

        class ClassDecl
          include ConstantUtil

          attr_reader :node
          attr_reader :members

          def initialize(node)
            @node = node
            @members = []
          end

          def class_name
             type_name(node.constant_path)
          end
        end
      end
    end
  end
end
