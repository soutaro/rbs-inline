# frozen_string_literal: true

require "test_helper"

class RBS::Inline::ParserTest < Minitest::Test
  include RBS::Inline

  def parse_ruby(src)
    Prism.parse(src, filepath: "a.rb")
  end

  def test_class_decl
    Parser.parse(parse_ruby(<<~RUBY), opt_in: false)
      class Foo
        # Hello world
        class Bar < Object
          def foo
          end
        end
      end
    RUBY
  end

  def test_stop_parsing
    assert_nil Parser.parse(parse_ruby(<<~RUBY), opt_in: false)
      # rbs_inline: disabled
      class Foo
      end
    RUBY

    assert_nil Parser.parse(parse_ruby(<<~RUBY), opt_in: true)
      class Foo
      end
    RUBY
  end

  def test_continue_parsing
    refute_nil Parser.parse(parse_ruby(<<~RUBY), opt_in: true)
      # rbs_inline: enabled

      class Foo
      end
    RUBY

    refute_nil Parser.parse(parse_ruby(<<~RUBY), opt_in: false)
      class Foo
      end
    RUBY
  end

  def test_block_parsing
    _, decls = Parser.parse(parse_ruby(<<~RUBY), opt_in: false)
      controller do
      end

      module Foo
        # @rbs module ClassMethods
        class_methods do
          def foo() = 123
        end
      end
    RUBY

    assert_equal 2, decls.size
    decls[0].tap do |decl|
      assert_instance_of AST::Declarations::BlockDecl, decl
      assert_nil decl.module_class_annotation
    end
    decls[1].tap do |decl|
      assert_instance_of AST::Declarations::ModuleDecl, decl
      assert_equal 1, decl.members.size
      decl.members[0].tap do |member|
        assert_instance_of AST::Declarations::BlockDecl, member
        assert_instance_of AST::Annotations::ModuleDecl, member.module_class_annotation
      end
    end
  end

  def test_data_assign_decl
    _, decls = Parser.parse(parse_ruby(<<~RUBY), opt_in: false)
      Account = Data.define(
        :id, #: String
        :email,
      )

      class Account
        Group = _ = Data.define(
          :name,  #: String
        )
      end
    RUBY

    assert_equal 2, decls.size
    decls[0].tap do |decl|
      assert_instance_of AST::Declarations::DataAssignDecl, decl
      attrs = decl.each_attribute.to_h
      attrs[:id].tap do |type|
        assert_equal "String", type.type.to_s
      end
      attrs[:email].tap do |type|
        assert_nil type
      end
    end
    decls[1].tap do |decl|
      assert_instance_of AST::Declarations::ClassDecl, decl

      decl.members[0].tap do |decl|
        assert_instance_of AST::Declarations::DataAssignDecl, decl
        attrs = decl.each_attribute.to_h
        attrs[:name].tap do |type|
          assert_equal "String", type.type.to_s
        end
      end
    end
  end

  def test_struct_assign_decl
    _, decls = Parser.parse(parse_ruby(<<~RUBY), opt_in: false)
      Account = Struct.new(
        :id, #: String
        :email
      )

      class Account
        # @rbs %a{rbs-inline:new-args=required}
        # @rbs %a{rbs-inline:readonly-attributes=true}
        Group = _ = Struct.new(
          :name,  #: String
          keyword_init: true
        )
      end
    RUBY

    assert_equal 2, decls.size
    decls[0].tap do |decl|
      assert_instance_of AST::Declarations::StructAssignDecl, decl
      attrs = decl.each_attribute.to_h
      attrs[:id].tap do |type|
        assert_equal "String", type.type.to_s
      end
      attrs[:email].tap do |type|
        assert_nil type
      end
      assert_predicate decl, :keyword_init?
      assert_predicate decl, :positional_init?
    end
    decls[1].tap do |decl|
      assert_instance_of AST::Declarations::ClassDecl, decl

      decl.members[0].tap do |decl|
        assert_instance_of AST::Declarations::StructAssignDecl, decl
        attrs = decl.each_attribute.to_h
        attrs[:name].tap do |type|
          assert_equal "String", type.type.to_s
        end
        assert_predicate decl, :keyword_init?
        refute_predicate decl, :positional_init?
      end
    end
  end

  def test_toplevel__constructs
    Parser.parse(parse_ruby(<<~RUBY), opt_in: false)
      include Foo
      extend Bar
      prepend Baz

      public
      private
      module_function

      def foo
      end
    RUBY
  end

  def test_def_decl
    _, decls = Parser.parse(parse_ruby(<<~RUBY), opt_in: false)
      class Account
        def foo
          # Do not parse definitions inside methods
          def bar; end

          private
        end
      end
    RUBY

    assert_equal 1, decls.size
    decls[0].tap do |decl|
      assert_instance_of AST::Declarations::ClassDecl, decl
      assert_equal 1, decl.members.size
      decl.members[0].tap do |member|
        assert_instance_of AST::Members::RubyDef, member
        assert_equal :foo, member.node.name
      end
    end
  end

  def test_ivar_decl
    _, decls = Parser.parse(parse_ruby(<<~RUBY), opt_in: false)
      class Account
        @civar1 = 123
        @civar2 = 123.0 #: Float
        @civar3 ||= "foo" #: String

        def foo
          @ivar1 = 123
          @ivar2 = 123.0 #: Float
          @ivar3 ||= "foo" #: String
        end
      end
    RUBY

    default_type = RBS::Types::Bases::Any.new(location: nil)

    assert_equal 1, decls.size
    decls[0].tap do |decl|
      assert_instance_of AST::Declarations::ClassDecl, decl
      assert_equal 7, decl.members.size
      decl.members[0].tap do |member|
        assert_instance_of AST::Members::RubyIvar, member
        assert_equal :@civar1, member.node.name
        assert_equal "untyped", member.rbs(default_type).type.to_s
      end
      decl.members[1].tap do |member|
        assert_instance_of AST::Members::RubyIvar, member
        assert_equal :@civar2, member.node.name
        assert_equal "Float", member.rbs(default_type).type.to_s
      end
      decl.members[2].tap do |member|
        assert_instance_of AST::Members::RubyIvar, member
        assert_equal :@civar3, member.node.name
        assert_equal "String", member.rbs(default_type).type.to_s
      end
      decl.members[3].tap do |member|
        assert_instance_of AST::Members::RubyDef, member
        assert_equal :foo, member.node.name
      end
      decl.members[4].tap do |member|
        assert_instance_of AST::Members::RubyIvar, member
        assert_equal :@ivar1, member.node.name
        assert_equal "untyped", member.rbs(default_type, nil).type.to_s
      end
      decl.members[5].tap do |member|
        assert_instance_of AST::Members::RubyIvar, member
        assert_equal :@ivar2, member.node.name
        assert_equal "Float", member.rbs(default_type).type.to_s
      end
      decl.members[6].tap do |member|
        assert_instance_of AST::Members::RubyIvar, member
        assert_equal :@ivar3, member.node.name
        assert_equal "String", member.rbs(default_type).type.to_s
      end
    end
  end

  def test_cvar_decl
    _, decls = Parser.parse(parse_ruby(<<~RUBY), opt_in: false)
      class Account
        @@cvar1 = 123
        @@cvar2 = 123.0 #: Float
        @@cvar3 ||= "foo" #: String

        def foo
          @@cvar4 = 123
          @@cvar5 = 123.0 #: Float
          @@cvar6 ||= "foo" #: String
        end
      end
    RUBY

    default_type = RBS::Types::Bases::Any.new(location: nil)

    assert_equal 1, decls.size
    decls[0].tap do |decl|
      assert_instance_of AST::Declarations::ClassDecl, decl
      assert_equal 7, decl.members.size
      decl.members[0].tap do |member|
        assert_instance_of AST::Members::RubyIvar, member
        assert_equal :@@cvar1, member.node.name
        assert_equal "untyped", member.rbs(default_type).type.to_s
      end
      decl.members[1].tap do |member|
        assert_instance_of AST::Members::RubyIvar, member
        assert_equal :@@cvar2, member.node.name
        assert_equal "Float", member.rbs(default_type).type.to_s
      end
      decl.members[2].tap do |member|
        assert_instance_of AST::Members::RubyIvar, member
        assert_equal :@@cvar3, member.node.name
        assert_equal "String", member.rbs(default_type).type.to_s
      end
      decl.members[3].tap do |member|
        assert_instance_of AST::Members::RubyDef, member
        assert_equal :foo, member.node.name
      end
      decl.members[4].tap do |member|
        assert_instance_of AST::Members::RubyIvar, member
        assert_equal :@@cvar4, member.node.name
        assert_equal "untyped", member.rbs(default_type).type.to_s
      end
      decl.members[5].tap do |member|
        assert_instance_of AST::Members::RubyIvar, member
        assert_equal :@@cvar5, member.node.name
        assert_equal "Float", member.rbs(default_type).type.to_s
      end
      decl.members[6].tap do |member|
        assert_instance_of AST::Members::RubyIvar, member
        assert_equal :@@cvar6, member.node.name
        assert_equal "String", member.rbs(default_type).type.to_s
      end
    end
  end
end
