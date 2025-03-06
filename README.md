# RBS::Inline

RBS::Inline allows embedding RBS type declarations into Ruby code as comments. You can declare types, write the implementation, and verifies they are consistent without leaving the editor opening the Ruby code.

> [!IMPORTANT]
> The maintainer is working to implement the inline RBS syntax to rbs-gem itself.
> This repository is not actively updated.

> [!IMPORTANT]
> This gem is a prototype for testing. We plan to merge this feature to rbs-gem and deprecate rbs-inline gem after that.

Here is a quick example of embedded declarations.

```rb
# rbs_inline: enabled

class Person
  attr_reader :name #: String

  attr_reader :addresses #: Array[String]

  # You can write the type of parameters and return types.
  #
  # @rbs name: String
  # @rbs addresses: Array[String]
  # @rbs return: void
  def initialize(name:, addresses:)
    @name = name
    @addresses = addresses
  end

  # Or write the type of the method just after `@rbs` keyword.
  #
  # @rbs () -> String
  def to_s
    "Person(name = #{name}, addresses = #{addresses.join(", ")})"
  end

  # The `:` syntax is the shortest one.
  #
  #: () -> String
  def hash
    [name, addresses].hash
  end

  # @rbs &block: (String) -> void
  def each_address(&block) #: void
    addresses.each(&block)
  end
end
```

This is equivalent to the following RBS type definition.

```rbs
class Person
  attr_reader name: String

  attr_reader addresses: Array[String]

  def initialize: (name: String, addresses: Array[String]) -> void

  def to_s: () -> String

  def each_address: () { (String) -> void } -> void
end
```

## Installation

Install the gem and add to the application's Gemfile by executing:

    $ bundle add rbs-inline --require=false

Note that the `--require=false` is important to avoid having type definition dependencies to this gem, which is usually unnecessary.

You can of course add a `gem` call in your Gemfile yourself.

```rb
gem 'rbs-inline', require: false
```

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install rbs-inline

## Usage

The gem works as a transpiler from annotated Ruby code to RBS files. Run `rbs-inline` command to generate RBS files, and use the generated files with Steep, or any tools which supports RBS type definitions.

```sh
# Print generated RBS files
$ bundle exec rbs-inline lib

# Save generated RBS files under sig/generated
$ bundle exec rbs-inline --output lib
```

You may want to use `fswatch` or likes to automatically generate RBS files when you edit the Ruby code.

    $ fswatch -0 lib | xargs -0 -n1 bundle exec rbs-inline --output

## More materials

[Our wiki](https://github.com/soutaro/rbs-inline/wiki) has some materials to read.

* [Syntax guide](https://github.com/soutaro/rbs-inline/wiki/Syntax-guide) explains more details of the syntax and annotations.
* [Roadmap](https://github.com/soutaro/rbs-inline/wiki/Roadmap) explains some of the missing features and our plans.
* [Snippets](https://github.com/soutaro/rbs-inline/wiki/Snippets) helps setting up your editors.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/soutaro/rbs-inline. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/soutaro/rbs-inline/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Rbs::Inline project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/soutaro/rbs-inline/blob/main/CODE_OF_CONDUCT.md).
