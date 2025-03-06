# rbs_inline: enabled

require 'stringio'

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

      attr_accessor :default_type #: Types::t

      # @rbs buffer: String
      def initialize(buffer = +"") #: void
        @output = buffer
        @writer = RBS::Writer.new(out: StringIO.new(buffer))
        @default_type = Types::Bases::Any.new(location: nil)
      end

      # @rbs uses: Array[AST::Annotations::Use]
      # @rbs decls: Array[AST::Declarations::t]
      # @rbs rbs_decls: Array[RBS::AST::Declarations::t]
      # @rbs &: ? (Writer) -> void
      def self.write(uses, decls, rbs_decls, &) #: void
        writer = Writer.new()
        yield writer if block_given?
        writer.write(uses, decls, rbs_decls)
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
      # @rbs rbs_decls: Array[RBS::AST::Declarations::t] --
      #    Top level `rbs!` declarations
      # @rbs return: void
      def write(uses, decls, rbs_decls)
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

        rbs.concat(rbs_decls)

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
        when AST::Declarations::DataAssignDecl
          translate_data_assign_decl(decl, rbs)
        when AST::Declarations::StructAssignDecl
          translate_struct_assign_decl(decl, rbs)
        when AST::Declarations::BlockDecl
          if decl.module_class_annotation
            case decl.module_class_annotation
            when AST::Annotations::ModuleDecl
              translate_module_block_decl(decl, rbs)
            when AST::Annotations::ClassDecl
              translate_class_block_decl(decl, rbs)
            end
          end
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
            if member.module_class_annotation
              translate_decl(member, rbs)
            else
              translate_members(member.members, decl, rbs)
            end
          when AST::Declarations::ClassDecl, AST::Declarations::ModuleDecl, AST::Declarations::ConstantDecl, AST::Declarations::DataAssignDecl, AST::Declarations::StructAssignDecl
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

        self_types = decl.module_selfs.flat_map { _1.self_types }.compact

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
          type: constant_decl_to_type(decl),
          comment: comment,
          location: nil
        )
      end

      # @rbs decl: AST::Declarations::DataAssignDecl
      # @rbs rbs: _Content
      def translate_data_assign_decl(decl, rbs) #: void
        return unless decl.constant_name

        if decl.comments
          comment = RBS::AST::Comment.new(string: decl.comments.content(trim: true), location: nil)
        end

        attributes = decl.each_attribute.map do |name, type|
          RBS::AST::Members::AttrReader.new(
            name: name,
            type: type&.type || default_type,
            ivar_name: false,
            comment: nil,
            kind: :instance,
            annotations: [],
            visibility: nil,
            location: nil
          )
        end

        new = RBS::AST::Members::MethodDefinition.new(
          name: :new,
          kind: :singleton,
          overloads: [
            RBS::AST::Members::MethodDefinition::Overload.new(
              method_type: RBS::MethodType.new(
                type_params: [],
                type: Types::Function.empty(Types::Bases::Instance.new(location: nil)).update(
                  required_positionals: decl.each_attribute.map do |name, attr|
                    RBS::Types::Function::Param.new(
                      type: attr&.type || default_type,
                      name: name,
                      location: nil
                    )
                  end
                ),
                block: nil,
                location: nil
              ),
              annotations: []
            ),
            RBS::AST::Members::MethodDefinition::Overload.new(
              method_type: RBS::MethodType.new(
                type_params: [],
                type: Types::Function.empty(Types::Bases::Instance.new(location: nil)).update(
                  required_keywords: decl.each_attribute.map do |name, attr|
                    [
                      name,
                      RBS::Types::Function::Param.new(
                        type: attr&.type || default_type,
                        name: nil,
                        location: nil
                      )
                    ]
                  end.to_h
                ),
                block: nil,
                location: nil
              ),
              annotations: []
            )
          ],
          annotations: [],
          location: nil,
          comment: nil,
          overloading: false,
          visibility: nil
        )

        members = [:singleton, :instance].map do |kind|
          RBS::AST::Members::MethodDefinition.new(
            name: :members,
            kind: kind, #: RBS::AST::MethodDefinition::Kind
            overloads: [
              RBS::AST::Members::MethodDefinition::Overload.new(
                method_type: RBS::MethodType.new(
                  type_params: [],
                  type: Types::Function.empty(
                    Types::Tuple.new(
                      types: decl.each_attribute.map do |name, _|
                        Types::Literal.new(literal: name, location: nil)
                      end,
                      location: nil
                    )
                  ),
                  block: nil,
                  location: nil
                ),
                annotations: []
              )
            ],
            annotations: [],
            location: nil,
            comment: nil,
            overloading: false,
            visibility: nil
          )
        end

        rbs << RBS::AST::Declarations::Class.new(
          name: decl.constant_name,
          type_params: [],
          members: [*attributes, new, *members],
          super_class: RBS::AST::Declarations::Class::Super.new(
            name: RBS::TypeName.new(name: :Data, namespace: RBS::Namespace.empty),
            args: [],
            location: nil
          ),
          annotations: decl.class_annotations,
          location: nil,
          comment: comment
        )
      end

      # @rbs decl: AST::Declarations::StructAssignDecl
      # @rbs rbs: _Content
      def translate_struct_assign_decl(decl, rbs) #: void
        return unless decl.constant_name

        if decl.comments
          comment = RBS::AST::Comment.new(string: decl.comments.content(trim: true), location: nil)
        end

        attributes = decl.each_attribute.map do |name, type|
          if decl.readonly_attributes?
            RBS::AST::Members::AttrReader.new(
              name: name,
              type: type&.type || default_type,
              ivar_name: false,
              comment: nil,
              kind: :instance,
              annotations: [],
              visibility: nil,
              location: nil
            )
          else
            RBS::AST::Members::AttrAccessor.new(
              name: name,
              type: type&.type || default_type,
              ivar_name: false,
              comment: nil,
              kind: :instance,
              annotations: [],
              visibility: nil,
              location: nil
            )
          end
        end

        new = RBS::AST::Members::MethodDefinition.new(
          name: :new,
          kind: :singleton,
          overloads: [],
          annotations: [],
          location: nil,
          comment: nil,
          overloading: false,
          visibility: nil
        )

        if decl.positional_init?
          attr_params = decl.each_attribute.map do |name, attr|
            RBS::Types::Function::Param.new(
              type: attr&.type || default_type,
              name: name,
              location: nil
            )
          end

          method_type = Types::Function.empty(Types::Bases::Instance.new(location: nil))
          if decl.required_new_args?
            method_type = method_type.update(required_positionals: attr_params)
          else
            method_type = method_type.update(optional_positionals: attr_params)
          end

          new.overloads <<
            RBS::AST::Members::MethodDefinition::Overload.new(
              method_type: RBS::MethodType.new(type_params: [], type: method_type, block: nil, location: nil),
              annotations: []
            )
        end

        if decl.keyword_init?
          attr_keywords = decl.each_attribute.map do |name, attr|
            [
              name,
              RBS::Types::Function::Param.new(
                type: attr&.type || default_type,
                name: nil,
                location: nil
              )
            ]
          end.to_h #: Hash[Symbol, RBS::Types::Function::Param]

          method_type = Types::Function.empty(Types::Bases::Instance.new(location: nil))
          if decl.required_new_args?
            method_type = method_type.update(required_keywords: attr_keywords)
          else
            method_type = method_type.update(optional_keywords: attr_keywords)
          end

          new.overloads <<
            RBS::AST::Members::MethodDefinition::Overload.new(
              method_type: RBS::MethodType.new(type_params: [], type: method_type, block: nil, location: nil),
              annotations: []
            )

          unless decl.positional_init?
            new.overloads <<
              RBS::AST::Members::MethodDefinition::Overload.new(
                method_type: RBS::MethodType.new(
                  type_params: [],
                  type: Types::Function.empty(Types::Bases::Instance.new(location: nil)).then do |t|
                    t.update(required_positionals: [
                      RBS::Types::Function::Param.new(
                        type: RBS::Types::Record.new(all_fields: decl.each_attribute.map do |name, attr|
                          [name, attr&.type || default_type]
                        end.to_h, location: nil),
                        name: nil,
                        location: nil
                      )
                    ])
                  end,
                  block: nil,
                  location: nil
                ),
                annotations:[]
              )
          end
        end

        rbs << RBS::AST::Declarations::Class.new(
          name: decl.constant_name,
          type_params: [],
          members: [*attributes, new],
          super_class: RBS::AST::Declarations::Class::Super.new(
            name: RBS::TypeName.new(name: :Struct, namespace: RBS::Namespace.empty),
            args: [
              RBS::Types::Union.new(
                types: decl.each_attribute.map { |_, attr| attr&.type || default_type }.uniq,
                location: nil
              )
            ],
            location: nil
          ),
          annotations: decl.class_annotations,
          location: nil,
          comment: comment
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

          visibility = member.visibility || decl&.visibility(member)
          rbs << RBS::AST::Members::MethodDefinition.new(
            name: member.method_name,
            kind: kind,
            overloads: member.method_overloads(default_type),
            annotations: member.method_annotations,
            location: nil,
            comment: comment,
            overloading: member.overloading?,
            visibility: visibility
          )
        when AST::Members::RubyAlias
          if member.comments
            comment = RBS::AST::Comment.new(string: member.comments.content(trim: true), location: nil)
          end

          kind = decl ? :singleton : :instance #: RBS::AST::Members::Alias::kind
          rbs << RBS::AST::Members::Alias.new(
            new_name: member.new_name,
            old_name: member.old_name,
            kind: kind,
            annotations: [],
            location: nil,
            comment: comment
          )
        when AST::Members::RubyMixin
          if m = member.rbs
            rbs << m
          end
        when AST::Members::RubyAttr
          if m = member.rbs(default_type)
            rbs.concat m
          end
        when AST::Members::RubyPrivate
          rbs << RBS::AST::Members::Private.new(location: nil) unless decl
        when AST::Members::RubyPublic
          rbs << RBS::AST::Members::Public.new(location: nil) unless decl
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
        return :singleton_instance if member.singleton_instance

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

      # @rbs decl: AST::Declarations::ConstantDecl
      # @rbs return: RBS::Types::t
      def constant_decl_to_type(decl)
        type = decl.type(default_type)
        return type unless type.is_a?(RBS::Types::ClassInstance)
        return type if type.args.any?

        case decl.node.value
        when Prism::ArrayNode
          RBS::BuiltinNames::Array.instance_type(default_type)
        when Prism::HashNode
          RBS::BuiltinNames::Hash.instance_type(default_type, default_type)
        else
          type
        end
      end
    end
  end
end
