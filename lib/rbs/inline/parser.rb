module RBS
  module Inline
    class Parser < Prism::Visitor
      attr_reader :decls, :surrounding_decls, :comments

      def initialize()
        @decls = []
        @surrounding_decls = []
        @comments = {}
      end

      def self.parse(result)
        instance = Parser.new()

        annots = AnnotationParser.parse(result.comments)
        annots.each do |result|
          instance.comments[result.line_range.end] = result
        end

        instance.visit(result.value)

        [
          [],
          instance.decls
        ]
      end

      def visit_class_node(node)
        visit node.constant_path
        visit node.superclass

        if node.location
          associated_comment = comments[node.location.start_line - 1]
        end

        class_decl = AST::Declarations::ClassDecl.new(node, associated_comment)

        push_class_module_decl(class_decl) do
          visit node.body
        end
      end

      def current_class_module_decl
        surrounding_decls.last
      end

      def push_class_module_decl(decl)
        if current = current_class_module_decl
          current.members << decl
        else
          decls << decl
        end

        surrounding_decls.push(decl)
        begin
          yield
        ensure
          surrounding_decls.pop()
        end
      end
    end
  end
end
