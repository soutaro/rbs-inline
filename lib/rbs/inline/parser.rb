# rbs_inline: enabled

# @rbs use Prism::*

module RBS
  module Inline
    class Parser < Prism::Visitor
      # The top level declarations
      #
      attr_reader :decls #:: Array[AST::Declarations::t]

      # The surrounding declarations
      #
      attr_reader :surrounding_decls #:: Array[AST::Declarations::ModuleDecl | AST::Declarations::ClassDecl]

      # ParsingResult associated with the line number at the end
      #
      # ```rb
      # # Hello
      # # world       <= The comments hash includes `2` (line 2) to the two lines
      # ```
      #
      # > [!IMPORTANT]
      # > The values will be removed during parsing.
      #
      attr_reader :comments #:: Hash[Integer, AnnotationParser::ParsingResult]

      # The current visibility applied to single `def` node
      #
      # Assuming it's directly inside `private` or `public` calls.
      # `nil` when the `def` node is not inside `private` or `public` calls.
      #
      attr_reader :current_visibility #:: RBS::AST::Members::visibility?

      def initialize() #:: void
        @decls = []
        @surrounding_decls = []
        @comments = {}
      end

      # @rbs result: ParseResult
      # @rbs opt_in: bool -- `true` for *opt-out* mode, `false` for *opt-in* mode.
      # @rbs return: [Array[AST::Annotations::Use], Array[AST::Declarations::t]]?
      def self.parse(result, opt_in:)
        instance = Parser.new()

        annots = AnnotationParser.parse(result.comments)
        annots.each do |result|
          instance.comments[result.line_range.end] = result
        end

        with_enable_magic_comment = result.comments.any? {|comment| comment.location.slice =~ /\A# rbs_inline: enabled\Z/}
        with_disable_magic_comment = result.comments.any? {|comment| comment.location.slice =~ /\A# rbs_inline: disabled\Z/}

        return if with_disable_magic_comment # Skips if `rbs_inline: disabled`

        if opt_in
          # opt-in means the `rbs_inline: enable` is required.
          return unless with_enable_magic_comment
        end

        uses = [] #: Array[AST::Annotations::Use]
        annots.each do |annot|
          annot.each_annotation do |annotation|
            if annotation.is_a?(AST::Annotations::Use)
              uses << annotation
            end
          end
        end

        instance.visit(result.value)

        [
          uses,
          instance.decls
        ]
      end

      # @rbs return: AST::Declarations::ModuleDecl | AST::Declarations::ClassDecl | nil
      def current_class_module_decl
        surrounding_decls.last
      end

      # @rbs return: AST::Declarations::ModuleDecl | AST::Declarations::ClassDecl
      def current_class_module_decl!
        current_class_module_decl or raise
      end

      #:: (AST::Declarations::ModuleDecl | AST::Declarations::ClassDecl | AST::Declarations::SingletonClassDecl) { () -> void } -> void
      #:: (AST::Declarations::ConstantDecl) -> void
      def push_class_module_decl(decl)
        if current = current_class_module_decl
          current.members << decl
        else
          decls << decl
        end

        if block_given?
          surrounding_decls.push(_ = decl)
          begin
            yield
          ensure
            surrounding_decls.pop()
          end
        end
      end

      # Load inner declarations and delete them from `#comments` hash
      #
      # It also sorts the `members` by `#start_line`` ascending.
      #
      # @rbs start_line: Integer
      # @rbs end_line: Integer
      # @rbs members: Array[AST::Members::t | AST::Declarations::t] --
      #   The destination.
      #   The method doesn't insert declarations, but have it to please type checker.
      def load_inner_annotations(start_line, end_line, members) #:: void
        comments = inner_annotations(start_line, end_line)

        comments.each do |comment|
          comment.each_annotation do |annotation|
            case annotation
            when AST::Annotations::IvarType
              members << AST::Members::RBSIvar.new(comment, annotation)
            when AST::Annotations::Embedded
              members << AST::Members::RBSEmbedded.new(comment, annotation)
            end
          end
        end

        members.sort_by! { _1.start_line }
      end

      # @rbs override
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

        load_inner_annotations(node.location.start_line, node.location.end_line, class_decl.members)
      end

      # @rbs override
      def visit_singleton_class_node(node)
        return if ignored_node?(node)

        associated_comment = comments.delete(node.location.start_line - 1)
        singleton_decl = AST::Declarations::SingletonClassDecl.new(node, associated_comment)

        push_class_module_decl(singleton_decl) do
          visit node.body
        end
      end

      # @rbs override
      def visit_module_node(node)
        return if ignored_node?(node)

        visit node.constant_path

        associated_comment = comments.delete(node.location.start_line - 1)

        module_decl = AST::Declarations::ModuleDecl.new(node, associated_comment)
        push_class_module_decl(module_decl) do
          visit node.body
        end

        load_inner_annotations(node.location.start_line, node.location.end_line, module_decl.members)
      end

      # Returns an array of annotations from comments that is located between start_line and end_line
      #
      # ```rb
      # module Foo        # line 1 (start_line)
      #   # foo
      #   # bar
      # end               # line 4 (end_line)
      # ```
      #
      # @rbs start_line: Integer
      # @rbs end_line: Integer
      def inner_annotations(start_line, end_line) #:: Array[AnnotationParser::ParsingResult]
        annotations = comments.each_value.select do |annotation|
          range = annotation.line_range
          start_line < range.begin && range.end < end_line
        end

        annotations.each do |annot|
          comments.delete(annot.line_range.end)
        end
      end

      # @rbs override
      def visit_def_node(node)
        return if ignored_node?(node)
        return unless current_class_module_decl

        current_decl = current_class_module_decl!

        if node.location
          associated_comment = comments.delete(node.location.start_line - 1)
        end

        assertion = assertion_annotation(node.rparen_loc || node&.parameters&.location || node.name_loc)

        current_decl.members << AST::Members::RubyDef.new(node, associated_comment, current_visibility, assertion)

        super
      end

      # @rbs override
      def visit_alias_method_node(node)
        return if ignored_node?(node)

        if node.location
          comment = comments.delete(node.location.start_line - 1)
        end
        current_class_module_decl!.members << AST::Members::RubyAlias.new(node, comment)
        super
      end

      # @rbs override
      def visit_call_node(node)
        return if ignored_node?(node)

        case node.name
        when :include, :prepend, :extend
          case node.receiver
          when nil, Prism::SelfNode
            comment = comments.delete(node.location.start_line - 1)
            app = application_annotation(node)

            current_class_module_decl!.members << AST::Members::RubyMixin.new(node, comment, app)

            return
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
              assertion = assertion_comment.each_annotation.find do |annotation|
                annotation.is_a?(AST::Annotations::Assertion)
              end #: AST::Annotations::Assertion?
            end

            current_class_module_decl!.members << AST::Members::RubyAttr.new(node, comment, assertion)

            return
          end
        when :public, :private
          case node.receiver
          when nil, Prism::SelfNode
            if node.arguments && node.arguments.arguments.size > 0
              if node.name == :public
                push_visibility(:public) { super }
              end

              if node.name == :private
                push_visibility(:private) { super }
              end

              return
            else
              if node.name == :public
                current_class_module_decl!.members << AST::Members::RubyPublic.new(node)
                return
              end

              if node.name == :private
                current_class_module_decl!.members << AST::Members::RubyPrivate.new(node)
                return
              end
            end
          end
        end

        super
      end

      # @rbs new_visibility: RBS::AST::Members::visibility?
      # @rbs &block: () -> void
      # @rbs return: void
      def push_visibility(new_visibility, &block)
        old_visibility = current_visibility

        begin
          @current_visibility = new_visibility
          yield
        ensure
          @current_visibility = old_visibility
        end
      end

      # @rbs node: Node
      # @rbs return: bool
      def ignored_node?(node)
        if comment = comments.fetch(node.location.start_line - 1, nil)
          comment.each_annotation.any? { _1.is_a?(AST::Annotations::Skip) }
        else
          false
        end
      end

      # Fetch Application annotation which is associated to `node`
      #
      # The application annotation is removed from `comments`.
      #
      # @rbs node: Node
      # @rbs return: AST::Annotations::Application?
      def application_annotation(node)
        comment_line, app_comment = comments.find do |_, comment|
          comment.line_range.begin == node.location.end_line
        end

        if app_comment && comment_line
          comments.delete(comment_line)
          app_comment.each_annotation.find do |annotation|
            annotation.is_a?(AST::Annotations::Application)
          end #: AST::Annotations::Application?
        end
      end

      # Fetch Assertion annotation which is associated to `node`
      #
      # The assertion annotation is removed from `comments`.
      #
      # @rbs node: Node | Location
      # @rbs return: AST::Annotations::Assertion?
      def assertion_annotation(node)
        if node.is_a?(Prism::Location)
          location = node
        else
          location = node.location
        end
        comment_line, app_comment = comments.find do |_, comment|
          comment.line_range.begin == location.end_line
        end

        if app_comment && comment_line
          comments.delete(comment_line)
          app_comment.each_annotation.find do |annotation|
            annotation.is_a?(AST::Annotations::Assertion)
          end #: AST::Annotations::Assertion?
        end
      end

      # @rbs override
      def visit_constant_write_node(node)
        return if ignored_node?(node)

        comment = comments.delete(node.location.start_line - 1)
        assertion = assertion_annotation(node)

        decl = AST::Declarations::ConstantDecl.new(node, comment, assertion)
        push_class_module_decl(decl)
      end
    end
  end
end
