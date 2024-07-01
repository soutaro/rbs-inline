# rbs_inline: enabled

require "optparse"

module RBS
  module Inline
    class CLI
      # Calculate the path under `output_path` that has the same structure relative to one of the `base_paths`
      #
      # ```rb
      # calculator = PathCalculator.new(Pathname("/rbs-inline"), [Pathname("app"), Pathname("lib")], Pathname("/tmp/sig"))
      # calculator.calculate(Pathname("/rbs-inline/app/models/foo.rb"))   # => Pathname("/tmp/sig/models/foo.rb")
      # calculator.calculate(Pathname("/rbs-inline/lib/bar.rb"))          # => Pathname("/tmp/sig/bar.rb")
      # calculator.calculate(Pathname("/rbs-inline/hello/world.rb"))      # => Pathname("/tmp/sig/hello/world.rb")
      # calculator.calculate(Pathname("/foo.rb"))                         # => nil
      # ```
      #
      #
      class PathCalculator
        attr_reader :pwd #: Pathname

        attr_reader :base_paths #: Array[Pathname]

        attr_reader :output_path #: Pathname

        # @rbs pwd: Pathname
        # @rbs base_paths: Array[Pathname]
        # @rbs output_path: Pathname
        def initialize(pwd, base_paths, output_path) #: void
          @pwd = pwd
          @base_paths = base_paths
          @output_path = output_path
        end

        #: (Pathname) -> Pathname?
        def calculate(path)
          path = pwd + path if path.relative?
          path = path.cleanpath
          return nil unless has_prefix?(path, prefix: pwd)

          if prefix = base_paths.find {|base| has_prefix?(path, prefix: pwd + base) }
            relative_to_output = path.relative_path_from(pwd + prefix)
          else
            relative_to_output = path.relative_path_from(pwd)
          end

          output_path + relative_to_output
        end

        # @rbs path: Pathname
        # @rbs prefix: Pathname
        # @rbs return: bool
        def has_prefix?(path, prefix:)
          path.descend.include?(prefix)
        end
      end

      attr_reader :stdout, :stderr #: IO
      attr_reader :logger #: Logger

      # @rbs stdout: IO
      # @rbs stderr: IO
      def initialize(stdout: STDOUT, stderr: STDERR) #: void
        @stdout = stdout
        @stderr = stderr
        @logger = Logger.new(stderr)
        logger.level = :ERROR
      end

      # @rbs args: Array[String]
      # @rbs return: Integer
      def run(args)
        base_paths = [Pathname("lib"), Pathname("app")]
        output_path = nil #: Pathname?
        opt_in = true

        OptionParser.new do |opts|
          opts.on("--base=BASE", "The path to calculate relative path of files (defaults to #{base_paths.join(File::PATH_SEPARATOR)})") do |str|
            # @type var str: String
            base_paths = str.split(File::PATH_SEPARATOR).map {|path| Pathname(path) }
          end

          opts.on("--output[=DEST]", "Save the generated RBS files under `sig/generated` or DEST if specified (defaults to output to STDOUT)") do
            if _1
              output_path = Pathname(_1)
            else
              output_path = Pathname("sig/generated")
            end
          end

          opts.on("--opt-out", "Generates RBS files by default. Opt-out with `# rbs_inline: disabled` comment") do
            opt_in = false
          end

          opts.on("--opt-in", "Generates RBS files only for files with `# rbs_inline: enabled` comment (default)") do
            opt_in = true
          end

          opts.on("--verbose") do
            logger.level = :DEBUG
          end
        end.parse!(args)

        logger.debug { "base_paths = #{base_paths.join(File::PATH_SEPARATOR)}, output_path = #{output_path}" }

        if output_path
          calculator = PathCalculator.new(Pathname.pwd, base_paths, output_path)
        end

        targets = args.flat_map { Pathname.glob(_1) }.flat_map do |path|
          if path.directory?
            pattern = path + "**/*.rb"
            Pathname.glob(pattern.to_s)
          else
            path
          end
        end

        targets.sort!
        targets.uniq!

        count = 0

        targets.each do |target|
          absolute_path = Pathname.pwd + target

          if output_path && calculator
            output_file_path = calculator.calculate(absolute_path)
            if output_file_path
              output = output_file_path.sub_ext(".rbs")
            else
              raise "Cannot calculate the output file path for #{target} in #{output_path}: calculated = #{output}"
            end

            logger.debug { "Generating #{output} from #{target} ..." }
          else
            logger.debug { "Generating RBS declaration from #{target} ..." }
          end

          logger.debug { "Parsing ruby file #{target}..." }

          if (uses, decls, rbs_decls = Parser.parse(Prism.parse_file(target.to_s), opt_in: opt_in))
            writer = Writer.new()
            writer.header("Generated from #{target.relative? ? target : target.relative_path_from(Pathname.pwd)} with RBS::Inline")
            writer.write(uses, decls, rbs_decls)

            if output
              unless output.parent.directory?
                logger.debug { "Making directory #{output.parent}..." }
                output.parent.mkpath
              end

              if output.file? && output.read == writer.output
                logger.debug { "Skip writing identical RBS file" }
              else
                logger.debug { "Writing RBS file to #{output}..." }
                output.write(writer.output)
                count += 1
              end
            else
              stdout.puts writer.output
              stdout.puts
              count += 1
            end
          else
            logger.debug { "Skipping #{target} because `# rbs_inline: enabled` comment not found" }
          end
        end

        stderr.puts "🎉 Generated #{count} RBS files under #{output_path}"

        0
      end
    end
  end
end
