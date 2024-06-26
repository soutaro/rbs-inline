# rbs_inline: enabled

module RBS
  module Inline
    class Writer
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

        rbs = decls.filter_map do |decl|
          translate_decl(decl)
        end

        writer.write(use_dirs + rbs)
      end

      # @rbs decl: AST::Declarations::t
      # @rbs return: RBS::AST::Declarations::t?
      def translate_decl(decl)
        case decl
        when AST::Declarations::ClassDecl
          translate_class_decl(decl)
        when AST::Declarations::ModuleDecl
          translate_module_decl(decl)
        when AST::Declarations::ConstantDecl
          translate_constant_decl(decl)
        end
      end

      # @rbs decl: AST::Declarations::ClassDecl
      # @rbs return: RBS::AST::Declarations::Class?
      def translate_class_decl(decl)
        return unless decl.class_name

        if decl.comments
          comment = RBS::AST::Comment.new(string: decl.comments.content(trim: true), location: nil)
        end

        members = [] #: Array[RBS::AST::Members::t | RBS::AST::Declarations::t]

        decl.members.each do |member|
          if member.is_a?(AST::Members::Base)
            if rbs_member = translate_member(member, decl)
              members.concat rbs_member
            end
          end

          if member.is_a?(AST::Declarations::SingletonClassDecl)
            members.concat translate_singleton_decl(member)
          elsif member.is_a?(AST::Declarations::Base)
            if rbs = translate_decl(member)
              members << rbs
            end
          end
        end

        RBS::AST::Declarations::Class.new(
          name: decl.class_name,
          type_params: decl.type_params,
          members: members,
          super_class: decl.super_class,
          annotations: [],
          location: nil,
          comment: comment
        )
      end

      # @rbs decl: AST::Declarations::ModuleDecl
      # @rbs return: RBS::AST::Declarations::Module?
      def translate_module_decl(decl)
        return unless decl.module_name

        if decl.comments
          comment = RBS::AST::Comment.new(string: decl.comments.content(trim: true), location: nil)
        end

        members = [] #: Array[RBS::AST::Members::t | RBS::AST::Declarations::t]

        decl.members.each do |member|
          if member.is_a?(AST::Members::Base)
            if rbs_member = translate_member(member, decl)
              members.concat rbs_member
            end
          end

          if member.is_a?(AST::Declarations::SingletonClassDecl)
            members.concat translate_singleton_decl(member)
          elsif member.is_a?(AST::Declarations::Base)
            if rbs = translate_decl(member)
              members << rbs
            end
          end
        end

        self_types = decl.module_selfs.map { _1.constraint }.compact

        RBS::AST::Declarations::Module.new(
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
      # @rbs return: RBS::AST::Declarations::Constant?
      def translate_constant_decl(decl)
        return unless decl.constant_name

        if decl.comments
          comment = RBS::AST::Comment.new(string: decl.comments.content(trim: true), location: nil)
        end

        RBS::AST::Declarations::Constant.new(
          name: decl.constant_name,
          type: decl.type,
          comment: comment,
          location: nil
        )
      end

      # @rbs decl: AST::Declarations::SingletonClassDecl
      # @rbs return: Array[RBS::AST::Members::t]
      def translate_singleton_decl(decl)
        members = []

        decl.members.each do |member|
          if member.is_a?(AST::Members::Base)
            if rbs_member = translate_member(member, decl)
              members.concat rbs_member
            end
          end
        end

        members
      end

      # @rbs member: AST::Members::t
      # @rbs decl: AST::Declarations::ClassDecl | AST::Declarations::ModuleDecl | AST::Declarations::SingletonClassDecl
      # @rbs return: Array[RBS::AST::Members::t | RBS::AST::Declarations::t]?
      def translate_member(member, decl)
        case member
        when AST::Members::RubyDef
          if member.comments
            comment = RBS::AST::Comment.new(string: member.comments.content(trim: true), location: nil)
          end

          kind = method_kind(member, decl)

          if member.override_annotation
            return [
              RBS::AST::Members::MethodDefinition.new(
                name: member.method_name,
                kind: kind,
                overloads: [],
                annotations: [],
                location: nil,
                comment: comment,
                overloading: true,
                visibility: member.visibility
              )
            ]
          end

          [
            RBS::AST::Members::MethodDefinition.new(
              name: member.method_name,
              kind: kind,
              overloads: member.method_overloads,
              annotations: member.method_annotations,
              location: nil,
              comment: comment,
              overloading: member.overloading?,
              visibility: member.visibility
            )
          ]
        when AST::Members::RubyAlias
          if member.comments
            comment = RBS::AST::Comment.new(string: member.comments.content(trim: true), location: nil)
          end

          [
            RBS::AST::Members::Alias.new(
              new_name: member.new_name,
              old_name: member.old_name,
              kind: :instance,
              annotations: [],
              location: nil,
              comment: comment
            )
          ]
        when AST::Members::RubyMixin
          [member.rbs].compact
        when AST::Members::RubyAttr
          member.rbs
        when AST::Members::RubyPrivate
          [
            RBS::AST::Members::Private.new(location: nil)
          ]
        when AST::Members::RubyPublic
          [
            RBS::AST::Members::Public.new(location: nil)
          ]
        when AST::Members::RBSIvar
          [
            member.rbs
          ].compact
        when AST::Members::RBSEmbedded
          case members = member.members
          when Array
            members
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
      # @rbs decl: AST::Declarations::ClassDecl | AST::Declarations::ModuleDecl | AST::Declarations::SingletonClassDecl
      # @rbs return: RBS::AST::Members::MethodDefinition::kind
      def method_kind(member, decl)
        return :singleton if decl.is_a?(AST::Declarations::SingletonClassDecl)

        case member.node.receiver
        when Prism::SelfNode
          :singleton
        else
          :instance
        end
      end
    end
  end
end
