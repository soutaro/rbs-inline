module RBS
  module Inline
    module AST
      module Annotations
        class Base
          attr_reader :source
        end

        class VarType < Base
          attr_reader :name
          attr_reader :type

          def initialize(name, type, source)
            @name = name
            @type = type
            @source = source
          end

          def complete?
            if name && type
              true
            else
              false
            end
          end
        end
      end
    end
  end
end
