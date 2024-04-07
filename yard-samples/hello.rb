require "prism"

ast = Prism.parse_file("yard-samples/sample1.rb")

pp ast.value
pp ast.comments
