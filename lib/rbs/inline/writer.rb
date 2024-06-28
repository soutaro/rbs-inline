# rbs_inline: enabled

module RBS
  module Inline
    class Writer
      # @rbs!
      #   interface _Content
      #     def <<: (RBS::AST::Declarations::t | RBS::AST::Members::t) -> void
      #
      #     def concat: (Array[RBS::AST::Declarations::t | RBS::AST::Members::t]) -> void
      #   end

      attr_reader :output #: String
      attr_reader :writer #: RBS::Writer

      # @rbs buffer: String
      def initialize(buffer = +"") #: void
        @output = buffer
        @writer = RBS::Writer.new(out: StringIO.new(buffer))
      end

      # @rbs uses: Array[AST::Annotations::Use]
      # @rbs decls: Array[AST::Declarations::t]
      def self.write(uses, decls) #: void
        writer = Writer.new()
        writer.write(uses, decls)
        writer.output
      end

      # @rbs *lines: String
      # @rbs return: void
      def header(*lines)
        lines.each do |line|
          writer.out.puts("# " + line)
        end
        writer.out.puts
      end

      # @rbs uses: Array[AST::Annotations::Use]
      # @rbs decls: Array[AST::Declarations::t]
      # @rbs return: void
      def write(uses, decls)
        use_dirs = uses.map do |use|
          RBS::AST::Directives::Use.new(
            clauses: use.clauses,
            location: nil
          )
        end

        rbs = [] #: Array[RBS::AST::Declarations::t]

        decls.each do |decl|
          translate_decl(
            decl,
            rbs #: Array[RBS::AST::Declarations::t | RBS::AST::Members::t]
          )
        end

        writer.write(
          use_dirs + rbs
        )
      end

      # @rbs decl: AST::Declarations::t
      # @rbs rbs: _Content
      # @rbs return: void
      def translate_decl(decl, rbs)
        case decl
        when AST::Declarations::ClassDecl
          translate_class_decl(decl, rbs)
        when AST::Declarations::ModuleDecl
          translate_module_decl(decl, rbs)
        when AST::Declarations::ConstantDecl
          translate_constant_decl(decl, rbs)
        end
      end

      # @rbs decl: AST::Declarations::ClassDecl
      # @rbs rbs: _Content
      # @rbs return: void
      def translate_class_decl(decl, rbs)
        return unless decl.class_name

        if decl.comments
          comment = RBS::AST::Comment.new(string: decl.comments.content(trim: true), location: nil)
        end

        members = [] #: Array[RBS::AST::Members::t | RBS::AST::Declarations::t]

        translate_members(decl.members, nil, members)

        rbs << RBS::AST::Declarations::Class.new(
          name: decl.class_name,
          type_params: decl.type_params,
          members: members,
          super_class: decl.super_class,
          annotations: [],
          location: nil,
          comment: comment
        )
      end

      # @rbs members: Array[AST::Declarations::t | AST::Members::t]
      # @rbs decl: AST::Declarations::SingletonClassDecl?
      # @rbs rbs: _Content
      # @rbs return: void
      def translate_members(members, decl, rbs)
        members.each do |member|
          case member
          when AST::Members::Base
            translate_member(member, decl, rbs)
          when AST::Declarations::SingletonClassDecl
            translate_singleton_decl(member, rbs)
          when AST::Declarations::BlockDecl
            if annotation = member.module_class_annotation
              case annotation
              when AST::Annotations::ModuleDecl
                translate_module_block_decl(member, rbs)
              when AST::Annotations::ClassDecl
                translate_class_block_decl(member, rbs)
              end
            else
              translate_members(member.members, decl, rbs)
            end
          when AST::Declarations::ClassDecl, AST::Declarations::ModuleDecl, AST::Declarations::ConstantDecl
            translate_decl(member, rbs)
          end
        end
      end

      # @rbs decl: AST::Declarations::ModuleDecl
      # @rbs rbs: _Content
      # @rbs return: void
      def translate_module_decl(decl, rbs)
        return unless decl.module_name

        if decl.comments
          comment = RBS::AST::Comment.new(string: decl.comments.content(trim: true), location: nil)
        end

        members = [] #: Array[RBS::AST::Members::t | RBS::AST::Declarations::t]

        translate_members(decl.members, nil, members)

        self_types = decl.module_selfs.map { _1.constraint }.compact

        rbs << RBS::AST::Declarations::Module.new(
          name: decl.module_name,
          type_params: decl.type_params,
          members: members,
          self_types: self_types,
          annotations: [],
          location: nil,
          comment: comment
        )
      end

      # @rbs decl: AST::Declarations::ConstantDecl
      # @rbs rbs: _Content
      # @rbs return: void
      def translate_constant_decl(decl, rbs)
        return unless decl.constant_name

        if decl.comments
          comment = RBS::AST::Comment.new(string: decl.comments.content(trim: true), location: nil)
        end

        rbs << RBS::AST::Declarations::Constant.new(
          name: decl.constant_name,
          type: decl.type,
          comment: comment,
          location: nil
        )
      end

      # @rbs decl: AST::Declarations::SingletonClassDecl
      # @rbs rbs: _Content
      # @rbs return: void
      def translate_singleton_decl(decl, rbs)
        decl.members.each do |member|
          if member.is_a?(AST::Members::Base)
            translate_member(member, decl, rbs)
          end
        end
      end

      # @rbs member: AST::Members::t
      # @rbs decl: AST::Declarations::SingletonClassDecl? --
      #   The surrouding singleton class definition
      # @rbs rbs: _Content
      # @rbs return void
      def translate_member(member, decl, rbs)
        case member
        when AST::Members::RubyDef
          if member.comments
            comment = RBS::AST::Comment.new(string: member.comments.content(trim: true), location: nil)
          end

          kind = method_kind(member, decl)

          if member.override_annotation
            rbs << RBS::AST::Members::MethodDefinition.new(
              name: member.method_name,
              kind: kind,
              overloads: [],
              annotations: [],
              location: nil,
              comment: comment,
              overloading: true,
              visibility: member.visibility
            )
            return
          end

          rbs << RBS::AST::Members::MethodDefinition.new(
            name: member.method_name,
            kind: kind,
            overloads: member.method_overloads,
            annotations: member.method_annotations,
            location: nil,
            comment: comment,
            overloading: member.overloading?,
            visibility: member.visibility
          )
        when AST::Members::RubyAlias
          if member.comments
            comment = RBS::AST::Comment.new(string: member.comments.content(trim: true), location: nil)
          end

          rbs << RBS::AST::Members::Alias.new(
            new_name: member.new_name,
            old_name: member.old_name,
            kind: :instance,
            annotations: [],
            location: nil,
            comment: comment
          )
        when AST::Members::RubyMixin
          if m = member.rbs
            rbs << m
          end
        when AST::Members::RubyAttr
          if m = member.rbs
            rbs.concat m
          end
        when AST::Members::RubyPrivate
          rbs << RBS::AST::Members::Private.new(location: nil)
        when AST::Members::RubyPublic
          rbs << RBS::AST::Members::Public.new(location: nil)
        when AST::Members::RBSIvar
          if m = member.rbs
            rbs << m
          end
        when AST::Members::RBSEmbedded
          case members = member.members
          when Array
            rbs.concat members
          end
        end
      end

      private

      # Returns the `kind` of the method definition
      #
      # ```rb
      # def self.foo = ()    # :singleton
      # class A
      #   class << self
      #     def bar = ()     # :singleton
      #   end
      # end
      #
      # def object.foo = ()  # Not supported (returns :instance)
      # ```
      #
      # @rbs member: AST::Members::RubyDef
      # @rbs decl: AST::Declarations::SingletonClassDecl?
      # @rbs return: RBS::AST::Members::MethodDefinition::kind
      def method_kind(member, decl)
        return :singleton if decl

        case member.node.receiver
        when Prism::SelfNode
          :singleton
        else
          :instance
        end
      end

      # @rbs block: AST::Declarations::BlockDecl
      # @rbs rbs: _Content
      # @rbs return: void
      def translate_module_block_decl(block, rbs)
        annotation = block.module_class_annotation
        annotation.is_a?(AST::Annotations::ModuleDecl) or raise

        return unless annotation.name

        if block.comments
          comment = RBS::AST::Comment.new(string: block.comments.content(trim: true), location: nil)
        end

        members = [] #: Array[RBS::AST::Members::t | RBS::AST::Declarations::t]

        translate_members(block.members, nil, members)

        self_types = annotation.self_types

        rbs << RBS::AST::Declarations::Module.new(
          name: annotation.name,
          type_params: annotation.type_params,
          members: members,
          self_types: self_types,
          annotations: [],
          location: nil,
          comment: comment
        )
      end

      # @rbs block: AST::Declarations::BlockDecl
      # @rbs rbs: _Content
      # @rbs return: void
      def translate_class_block_decl(block, rbs)
        annotation = block.module_class_annotation
        annotation.is_a?(AST::Annotations::ClassDecl) or raise

        return unless annotation.name

        if block.comments
          comment = RBS::AST::Comment.new(string: block.comments.content(trim: true), location: nil)
        end

        members = [] #: Array[RBS::AST::Members::t | RBS::AST::Declarations::t]

        translate_members(block.members, nil, members)

        rbs << RBS::AST::Declarations::Class.new(
          name: annotation.name,
          type_params: annotation.type_params,
          members: members,
          super_class: annotation.super_class,
          annotations: [],
          location: nil,
          comment: comment
        )
      end
    end
  end
end
