# frozen_string_literal: true

require_relative "lib/rbs/inline/version"

Gem::Specification.new do |spec|
  spec.name = "rbs-inline"
  spec.version = RBS::Inline::VERSION
  spec.authors = ["Soutaro Matsumoto"]
  spec.email = ["matsumoto@soutaro.com"]

  spec.summary = "Inline RBS type declaration."
  spec.description = "Inline RBS type declaration."
  spec.homepage = "https://github.com/soutaro/rbs-inline"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/soutaro/rbs-inline"
  spec.metadata["changelog_uri"] = "https://github.com/soutaro/rbs-inline/blob/master/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "prism", ">= 0.29", "< 1.6"
  spec.add_dependency "rbs", ">= 3.5.0"
end
