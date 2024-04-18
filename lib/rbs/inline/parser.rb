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

        # pp result

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

      def current_class_module_decl
        surrounding_decls.last
      end

      def current_class_module_decl!
        current_class_module_decl or raise
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

      def visit_class_node(node)
        return if ignored_node?(node)

        visit node.constant_path
        visit node.superclass

        associated_comment = comments.delete(node.location.start_line - 1)
        if node.superclass
          app_comment = application_annotation(node.superclass)
        end

        class_decl = AST::Declarations::ClassDecl.new(node, associated_comment, app_comment)

        push_class_module_decl(class_decl) do
          visit node.body
        end
      end

      def visit_def_node(node)
        return if ignored_node?(node)
        return unless current_class_module_decl

        current_decl = current_class_module_decl!

        if node.location
          associated_comment = comments.delete(node.location.start_line - 1)
        end

        current_decl.members << AST::Members::RubyDef.new(node, associated_comment)

        super
      end

      def visit_alias_method_node(node)
        return if ignored_node?(node)

        if node.location
          comment = comments.delete(node.location.start_line - 1)
        end
        current_class_module_decl!.members << AST::Members::RubyAlias.new(node, comment)
        super
      end

      def visit_call_node(node)
        return if ignored_node?(node)

        case node.name
        when :include, :prepend, :extend
          case node.receiver
          when nil, Prism::SelfNode
            comment = comments.delete(node.location.start_line - 1)
            app = application_annotation(node)

            current_class_module_decl!.members << AST::Members::RubyMixin.new(node, comment, app)
          end
        when :attr_reader, :attr_accessor, :attr_writer
          case node.receiver
          when nil, Prism::SelfNode
            comment = comments.delete(node.location.start_line - 1)

            comment_line, assertion_comment = comments.find do |_, comment|
              comment.line_range.begin == node.location.end_line
            end
            if assertion_comment && comment_line
              comments.delete(comment_line)
              assertion = assertion_comment.annotations.find do |annotation|
                annotation.is_a?(AST::Annotations::Assertion)
              end #: AST::Annotations::Assertion?
            end

            current_class_module_decl!.members << AST::Members::RubyAttr.new(node, comment, assertion)
          end
        end

        super
      end

      def ignored_node?(node)
        if comment = comments.fetch(node.location.start_line - 1, nil)
          comment.annotations.any? { _1.is_a?(AST::Annotations::Skip) }
        else
          false
        end
      end

      def application_annotation(node)
        comment_line, app_comment = comments.find do |_, comment|
          comment.line_range.begin == node.location.end_line
        end

        if app_comment && comment_line
          comments.delete(comment_line)
          app = app_comment.annotations.find do |annotation|
            annotation.is_a?(AST::Annotations::Application)
          end #: AST::Annotations::Application?
        end
      end
    end
  end
end
