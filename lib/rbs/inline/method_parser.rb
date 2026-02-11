module RBS
  module Inline
    class MethodParser < Prism::Visitor
      # @rbs parser: Parser
      # @rbs node: Prism::DefNode
      # @rbs return: Array[AST::Members::RubyIvar]
      def self.parse(parser, node)
        parser = MethodParser.new(parser)
        parser.visit(node)
        parser.instance_variables
      end

      attr_reader :parser #: Parser
      attr_reader :instance_variables #: Array[AST::Members::RubyIvar]

      # @rbs parser: Parser
      def initialize(parser)
        @parser = parser
        @instance_variables = []
      end

      # @rbs override
      def visit_instance_variable_or_write_node(node)
        assertion = assertion_annotation(node)
        instance_variables << AST::Members::RubyIvar.new(node, assertion, scope: :method)
      end

      # @rbs override
      def visit_instance_variable_write_node(node)
        assertion = assertion_annotation(node)
        instance_variables << AST::Members::RubyIvar.new(node, assertion, scope: :method)
      end

      # @rbs override
      def visit_class_variable_or_write_node(node)
        assertion = assertion_annotation(node)
        instance_variables << AST::Members::RubyIvar.new(node, assertion, scope: :method)
      end

      # @rbs override
      def visit_class_variable_write_node(node)
        assertion = assertion_annotation(node)
        instance_variables << AST::Members::RubyIvar.new(node, assertion, scope: :method)
      end

      # Fetch TypeAssertion annotation which is associated to `node`
      #
      # The assertion annotation is removed from `comments`.
      #
      # @rbs node: Prism::Node | Prism::Location
      # @rbs return: AST::Annotations::TypeAssertion?
      def assertion_annotation(node)
        if node.is_a?(Prism::Location)
          location = node
        else
          location = node.location
        end
        comment_line, app_comment = parser.comments.find do |_, comment|
          comment.line_range.begin == location.end_line
        end

        if app_comment && comment_line
          parser.comments.delete(comment_line)
          app_comment.each_annotation.find do |annotation|
            annotation.is_a?(AST::Annotations::TypeAssertion)
          end #: AST::Annotations::TypeAssertion?
        end
      end
    end
  end
end
