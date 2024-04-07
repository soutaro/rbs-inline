module Foo
  # This is `Foo#foo` method
  #
  # @param i [Integer] Size of something
  # @param j [Symbol,Integer] Something doing meaningful
  # @return [String?] Returns a string or nil
  #
  #
  # @rbs.method (Integer, String) -> void
  #           | [A] () { () [self: String] -> A } -> A?
  #
  def foo(i, j)

  end

  # @rbs.inline
  #   attr_reader hoge: String
  #   attr_reader name: String?
  def hoge

  end

  class Foo
    # @rbs.inline include Foo[String]
  end
end
