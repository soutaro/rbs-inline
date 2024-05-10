# frozen_string_literal: true

require "test_helper"
require "rbs/inline/cli"

class RBS::Inline::CLITest < Minitest::Test
  include RBS::Inline

  def test_path_calculator
    calculator = CLI::PathCalculator.new(Pathname("/src"), [Pathname("app"), Pathname("lib")], Pathname("/sig"))

    assert_equal Pathname("/sig/foo.rb"), calculator.calculate(Pathname("/src/lib/foo.rb"))
    assert_equal Pathname("/sig/models/foo.rb"), calculator.calculate(Pathname("/src/app/models/foo.rb"))
    assert_equal Pathname("/sig/test/foo_test.rb"), calculator.calculate(Pathname("/src/test/foo_test.rb"))
    assert_nil calculator.calculate(Pathname("/app/foo.rb"))
  end

  def stdout
    @stdout ||= StringIO.new
  end

  def stderr
    @stderr ||= StringIO.new
  end

  def with_tmpdir
    Dir.mktmpdir do
      yield Pathname(_1)
    end
  end

  def test_cli__stdout
    with_tmpdir do |pwd|
      Dir.chdir(pwd.to_s) do
        cli = CLI.new(stdout: stdout, stderr: stderr)

        (pwd + "foo.rb").write(<<~RUBY)
          # rbs_inline: enabled

          class Hello
          end
        RUBY

        cli.run(%w(foo.rb -v))

        assert_equal <<~RBS, stdout.string
          # Generated from foo.rb with RBS::Inline

          class Hello
          end

        RBS
      end
    end
  end

  def test_cli__prefix
    with_tmpdir do |pwd|
      Dir.chdir(pwd.to_s) do
        cli = CLI.new(stdout: stdout, stderr: stderr)

        lib = pwd + "lib"
        lib.mkpath

        test = pwd + "test"
        test.mkpath

        (lib + "foo.rb").write(<<~RUBY)
          # rbs_inline: enabled

          class Hello
          end
        RUBY
        (test + "foo_test.rb").write(<<~RUBY)
          # rbs_inline: enabled

          class FooTest
          end
        RUBY

        cli.run(%w(lib test -v --output=sig))

        sig = pwd + "sig"
        assert_predicate (sig + "foo.rbs"), :file?
        assert_predicate (sig + "test/foo_test.rbs"), :file?
      end
    end
  end
end
