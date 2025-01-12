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

      Measure = Data.define(
        :amount, #: Integer
        :unit #: Integer
      ) do
        UNITS = [:meter, :inch]

        def <=>(other)
          return unless other.is_a?(self.class) && other.unit == unit
          amount <=> other.amount
        end

        include Comparable
      end
    RUBY

    assert_equal 4, decls.size
    decls[0].tap do |decl|
      assert_instance_of AST::Declarations::DataAssignDecl, decl
      attrs = decl.each_attribute.to_h
      attrs[:id].tap do |type|
        assert_equal "String", type.type.to_s
      end
      attrs[:email].tap do |type|
        assert_nil type
      end
      assert_equal [], decl.members
    end
    decls[1].tap do |decl|
      assert_instance_of AST::Declarations::ClassDecl, decl

      decl.members[0].tap do |decl|
        assert_instance_of AST::Declarations::DataAssignDecl, decl
        attrs = decl.each_attribute.to_h
        attrs[:name].tap do |type|
          assert_equal "String", type.type.to_s
        end
        assert_equal [], decl.members
      end
    end
    decls[2].tap do |decl|
      assert_instance_of AST::Declarations::DataAssignDecl, decl
      attrs = decl.each_attribute.to_h
      attrs[:amount].tap do |type|
        assert_equal "Integer", type.type.to_s
      end
      attrs[:unit].tap do |type|
        assert_equal "Integer", type.type.to_s
      end

      assert_equal 2, decl.members.size
      decl.members[0].tap do |member|
        assert_instance_of AST::Members::RubyDef, member
        assert_equal :<=>, member.node.name
      end
      decl.members[1].tap do |member|
        assert_instance_of AST::Members::RubyMixin, member
        assert_equal :include, member.node.name
      end
    end
    decls[3].tap do |decl|
      assert_instance_of AST::Declarations::ConstantDecl, decl
      assert_equal :UNITS, decl.node.name
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

      Measure = Struct.new(
        :amount, #: Integer
        :unit #: Integer
      ) do
        UNITS = [:meter, :inch]

        def <=>(other) #: bool
          return unless other.is_a?(self.class) && other.unit == unit
          amount <=> other.amount
        end

        include Comparable
      end
    RUBY

    assert_equal 4, decls.size
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
    decls[2].tap do |decl|
      assert_instance_of AST::Declarations::StructAssignDecl, decl
      attrs = decl.each_attribute.to_h
      attrs[:amount].tap do |type|
        assert_equal "Integer", type.type.to_s
      end
      attrs[:unit].tap do |type|
        assert_equal "Integer", type.type.to_s
      end
      assert_predicate decl, :keyword_init?
      assert_predicate decl, :positional_init?

      assert_equal 2, decl.members.size
      decl.members[0].tap do |member|
        assert_instance_of AST::Members::RubyDef, member
        assert_equal :<=>, member.node.name
      end
      decl.members[1].tap do |member|
        assert_instance_of AST::Members::RubyMixin, member
        assert_equal :include, member.node.name
      end
    end
    decls[3].tap do |decl|
      assert_instance_of AST::Declarations::ConstantDecl, decl
      assert_equal :UNITS, decl.node.name
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
end
