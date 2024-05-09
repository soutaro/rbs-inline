# rbs_inline: enabled

require "optparse"

module RBS
  module Inline
    class CLI
      attr_reader :stdout, :stderr #:: IO
      attr_reader :logger #:: Logger

      # @rbs stdout: IO
      # @rbs stderr: IO
      def initialize(stdout: STDOUT, stderr: STDERR) #:: void
        @stdout = stdout
        @stderr = stderr
        @logger = Logger.new(stderr)
        logger.level = :ERROR
      end

      # @rbs args: Array[String]
      # @rbs returns Integer
      def run(args)
        base_paths = [Pathname("lib"), Pathname("app")]
        output_path = nil #: Pathname?

        OptionParser.new do |opts|
          opts.on("--base=[BASE]", "The path to calculate relative path of files (defaults to #{base_paths.join(File::PATH_SEPARATOR)})") do |str|
            # @type var str: String
            base_paths = str.split(File::PATH_SEPARATOR).map {|path| Pathname(path) }
          end

          opts.on("--output=[BASE]", "The directory where the RBS files are saved at (defaults to STDOUT if not specified)") do
            output_path = Pathname(_1)
          end

          opts.on("--verbose") do
            logger.level = :DEBUG
          end
        end.parse!(args)

        logger.debug { "base_paths = #{base_paths.join(File::PATH_SEPARATOR)}, output_path = #{output_path}" }

        base_paths = base_paths.map { Pathname.pwd.join(_1) }

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

          base_path = base_paths.find do |path|
            target.descend.include?(path)
          end
          if base_path
            relative_path = absolute_path.relative_path_from(Pathname.pwd + base_path)
          else
            relative_path = absolute_path.relative_path_from(Pathname.pwd)
          end

          if output_path
            output = output_path + relative_path.sub_ext(".rbs")

            unless output.to_s.start_with?(output_path.to_s)
              raise "Cannot calculate the output file path for #{target} in #{output_path}: calculated = #{output}"
            end

            logger.debug { "Generating #{output} from #{target} ..." }
          else
            logger.debug { "Generating RBS declaration from #{target} ..." }
          end

          logger.debug { "Parsing ruby file #{target}..." }

          if (uses, decls = Parser.parse(Prism.parse_file(target.to_s)))
            writer = Writer.new()
            writer.header("Generated from #{target.relative? ? target : target.relative_path_from(Pathname.pwd)} with RBS::Inline")
            writer.write(uses, decls)

            if output
              unless output.parent.directory?
                logger.debug { "Making directory #{output.parent}..." }
                output.parent.mkpath
              end

              logger.debug { "Writing RBS file to #{output}..." }
              output.write(writer.output)
            else
              stdout.puts writer.output
              stdout.puts
            end

            count += 1
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
