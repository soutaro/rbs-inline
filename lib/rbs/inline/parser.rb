# rbs_inline: enabled

# @rbs use Prism::*

module RBS
  module Inline
    class Parser < Prism::Visitor
      # @rbs! type with_members = AST::Declarations::ModuleDecl
      #                         | AST::Declarations::ClassDecl
      #                         | AST::Declarations::SingletonClassDecl
      #                         | AST::Declarations::BlockDecl

      # The top level declarations
      #
      attr_reader :decls #: Array[AST::Declarations::t]

      # The surrounding declarations
      #
      attr_reader :surrounding_decls #: Array[with_members]

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
      attr_reader :comments #: Hash[Integer, AnnotationParser::ParsingResult]

      # The current visibility applied to single `def` node
      #
      # Assuming it's directly inside `private` or `public` calls.
      # `nil` when the `def` node is not inside `private` or `public` calls.
      #
      attr_reader :current_visibility #: RBS::AST::Members::visibility?

      # The current module_function applied to single `def` node
      attr_reader :current_module_function #: bool

      def initialize() #: void
        @decls = []
        @surrounding_decls = []
        @comments = {}
        @current_module_function = false
      end

      # Parses the given Prism result to a three tuple
      #
      # Returns a three tuple of:
      #
      # 1. An array of `use` directives
      # 2. An array of declarations
      # 3. An array of RBS declarations given as `@rbs!` annotation at top-level
      #
      # Note that only RBS declarations are allowed in the top-level `@rbs!` annotations.
      # RBS *members* are ignored in the array.
      #
      # @rbs result: ParseResult
      # @rbs opt_in: bool -- `true` for *opt-out* mode, `false` for *opt-in* mode.
      # @rbs return: [Array[AST::Annotations::Use], Array[AST::Declarations::t], Array[RBS::AST::Declarations::t]]?
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

        rbs_embeddeds = [] #: Array[AST::Members::RBSEmbedded]

        instance.comments.each_value do |comment|
          comment.each_annotation do |annotation|
            if annotation.is_a?(AST::Annotations::Embedded)
              rbs_embeddeds << AST::Members::RBSEmbedded.new(comment, annotation)
            end
          end
        end

        rbs_decls = rbs_embeddeds.flat_map do |embedded|
          if (members = embedded.members).is_a?(Array)
            members.select do |member|
              member.is_a?(RBS::AST::Declarations::Base)
            end
          else
            []
          end #: Array[RBS::AST::Declarations::t]
        end

        [
          uses,
          instance.decls,
          rbs_decls
        ]
      end

      # @rbs return: with_members?
      def current_class_module_decl
        surrounding_decls.last
      end

      # @rbs return: with_members
      def current_class_module_decl!
        current_class_module_decl or raise
      end

      #: (with_members) { () -> void } -> void
      def push_class_module_decl(decl)
        if current = current_class_module_decl
          current.members << decl
        else
          decls << decl
        end

        if block_given?
          surrounding_decls.push(decl)
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
      def load_inner_annotations(start_line, end_line, members) #: void
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
        process_nesting_node(node) do
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
      end

      # @rbs override
      def visit_singleton_class_node(node)
        process_nesting_node(node) do
          associated_comment = comments.delete(node.location.start_line - 1)
          singleton_decl = AST::Declarations::SingletonClassDecl.new(node, associated_comment)

          push_class_module_decl(singleton_decl) do
            visit node.body
          end

          load_inner_annotations(node.location.start_line, node.location.end_line, singleton_decl.members)
        end
      end

      # @rbs override
      def visit_module_node(node)
        process_nesting_node(node) do
          visit node.constant_path

          associated_comment = comments.delete(node.location.start_line - 1)

          module_decl = AST::Declarations::ModuleDecl.new(node, associated_comment)
          push_class_module_decl(module_decl) do
            visit node.body
          end

          load_inner_annotations(node.location.start_line, node.location.end_line, module_decl.members)
        end
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
      def inner_annotations(start_line, end_line) #: Array[AnnotationParser::ParsingResult]
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
        process_nesting_node(node) do
          return unless current_class_module_decl

          current_decl = current_class_module_decl!

          if node.location
            associated_comment = comments.delete(node.location.start_line - 1)
          end

          assertion = assertion_annotation(node.rparen_loc || node&.parameters&.location || node.name_loc)

          current_decl.members << AST::Members::RubyDef.new(node, associated_comment, current_visibility, current_module_function, assertion)
        end
      end

      # @rbs override
      def visit_alias_method_node(node)
        return if ignored_node?(node)
        return unless current_class_module_decl

        if node.location
          comment = comments.delete(node.location.start_line - 1)
        end
        current_class_module_decl!.members << AST::Members::RubyAlias.new(node, comment)
        super
      end

      # @rbs override
      def visit_call_node(node)
        return if ignored_node?(node)
        return super unless current_class_module_decl

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
                annotation.is_a?(AST::Annotations::TypeAssertion)
              end #: AST::Annotations::TypeAssertion?
            end

            current_class_module_decl!.members << AST::Members::RubyAttr.new(node, comment, current_visibility, assertion)

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
        when :module_function
          if node.arguments && node.arguments.arguments.size > 0
            args = node.arguments.arguments.filter_map do |arg|
              case arg
              when Prism::SymbolNode
                arg.unescaped.to_sym
              end
            end

            current_decl = current_class_module_decl

            if current_decl
              node.arguments.arguments.each do |arg|
                current_decl.members.each do |member|
                  if member.is_a?(AST::Members::RubyDef) && args.include?(member.node.name)
                    member.singleton_instance = true
                    break
                  end
                end
              end
            end
          else
            @current_module_function = true
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

      # @rbs [A] (Node) { () -> A } -> A?
      def process_nesting_node(node)
        yield unless ignored_node?(node)
      ensure
        # Delete all inner annotations
        inner_annotations(node.location.start_line, node.location.end_line)
        comments.delete(node.location.start_line)
        comments.delete(node.location.end_line)
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

      # Fetch TypeAssertion annotation which is associated to `node`
      #
      # The assertion annotation is removed from `comments`.
      #
      # @rbs node: Node | Location
      # @rbs return: AST::Annotations::TypeAssertion?
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
            annotation.is_a?(AST::Annotations::TypeAssertion)
          end #: AST::Annotations::TypeAssertion?
        end
      end

      # @rbs override
      def visit_constant_write_node(node)
        return if ignored_node?(node)

        comment = comments.delete(node.location.start_line - 1)

        case
        when data_node = AST::Declarations::DataAssignDecl.data_define?(node)
          type_decls = {} #: Hash[Integer, AST::Annotations::TypeAssertion]

          inner_annotations(node.location.start_line, node.location.end_line).flat_map do |comment|
            comment.each_annotation do |annotation|
              if annotation.is_a?(AST::Annotations::TypeAssertion)
                start_line = annotation.source.comments[0].location.start_line
                type_decls[start_line] = annotation
              end
            end
          end

          decl = AST::Declarations::DataAssignDecl.new(node, data_node, comment, type_decls)
        when struct_node = AST::Declarations::StructAssignDecl.struct_new?(node)
          type_decls = {} #: Hash[Integer, AST::Annotations::TypeAssertion]

          inner_annotations(node.location.start_line, node.location.end_line).flat_map do |comment|
            comment.each_annotation do |annotation|
              if annotation.is_a?(AST::Annotations::TypeAssertion)
                start_line = annotation.source.comments[0].location.start_line
                type_decls[start_line] = annotation
              end
            end
          end

          decl = AST::Declarations::StructAssignDecl.new(node, struct_node, comment, type_decls)
        else
          assertion = assertion_annotation(node)
          decl = AST::Declarations::ConstantDecl.new(node, comment, assertion)
        end

        if current = current_class_module_decl
          current.members << decl
        else
          decls << decl
        end
      end

      # @rbs override
      def visit_block_node(node)
        process_nesting_node(node) do
          comment = comments.delete(node.location.start_line - 1)
          block = AST::Declarations::BlockDecl.new(node, comment)

          push_class_module_decl(block) do
            super
          end

          load_inner_annotations(node.location.start_line, node.location.end_line, block.members)
        end
      end
    end
  end
end
