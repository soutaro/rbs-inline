module RBS
  module Inline
    module NodeUtils
      def type_name(node)
        case node
        when Prism::ConstantReadNode
          TypeName(node.name.to_s)
        end
      end
    end
  end
end
