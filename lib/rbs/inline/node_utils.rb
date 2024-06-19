# rbs_inline: enabled

module RBS
  module Inline
    module NodeUtils
      # @rbs node: Prism::Node
      # @rbs return: TypeName?
      def type_name(node)
        case node
        when Prism::ConstantReadNode
          TypeName(node.name.to_s)
        end
      end
    end
  end
end
