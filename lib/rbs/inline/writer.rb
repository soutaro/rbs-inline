module RBS
  module Inline
    class Writer
      attr_reader :output
      attr_reader :writer

      def initialize(buffer = +"")
        @output = buffer
        @writer = RBS::Writer.new(out: StringIO.new(buffer))
      end

      def self.write(uses, decls)
        writer = Writer.new()
        writer.write(uses, decls)
        writer.output
      end

      def write(uses, decls)
        decls.each do |decl|
          if klass_decl = translate_class_decl(decl)
            writer.write([klass_decl])
          end
        end
      end

      def translate_class_decl(decl)
        return unless decl.class_name

        if decl.comments
          comment = RBS::AST::Comment.new(string: decl.comments.content, location: nil)
        end

        members = [] #: Array[RBS::AST::Members::t | RBS::AST::Declarations::t]

        decl.members.each do |member|
          if member.is_a?(AST::Members::Base)
            if rbs_member = translate_member(member)
              members << rbs_member
            end
          end

          if member.is_a?(AST::Declarations::Base)
            if rbs_decl = translate_class_decl(member)
              members << rbs_decl
            end
          end
        end

        RBS::AST::Declarations::Class.new(
          name: decl.class_name,
          type_params: [],
          members: members,
          super_class: nil,
          annotations: [],
          location: nil,
          comment: comment
        )
      end

      def translate_member(member)
        case member
        when AST::Members::RubyDef
          if member.comments
            comment = RBS::AST::Comment.new(string: member.comments.content, location: nil)
          end

          RBS::AST::Members::MethodDefinition.new(
            name: member.method_name,
            kind: :instance,
            overloads: member.method_overloads,
            annotations: member.method_annotations,
            location: nil,
            comment: comment,
            overloading: false,
            visibility: nil
          )
        end
      end
    end
  end
end
