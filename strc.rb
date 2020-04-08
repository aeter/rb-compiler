#!/usr/bin/env ruby

# A super tiny compiler, modelled after
# https://github.com/jamiebuilds/the-super-tiny-compiler (JS)
# and
# https://github.com/hazbo/the-super-tiny-compiler (Go)


# ---------------------------------------------------------------------
# "(add 2 (subtract 4 2))"  |  [{:type=>"paren", :value=>"("},
#                           |   {:type=>"name", :value=>"add"},
#                           |   {:type=>"number", :value=>"2"},
#                           |   {:type=>"paren", :value=>"("},
#                           |   {:type=>"name", :value=>"subtract"},
#                           |   {:type=>"number", :value=>"4"},
#                           |   {:type=>"number", :value=>"2"},
#                           |   {:type=>"paren", :value=>")"},
#                           |   {:type=>"paren", :value=>")"}]
# ---------------------------------------------------------------------
def tokenize(input)
  current = 0 
  tokens = []
  while current < input.length
    char = input[current]  

    if char == '('
      tokens << { type: 'paren', value: '(' }
      current += 1
      next
    end

    if char == ')'
      tokens << { type: 'paren', value: ')' }
      current += 1
      next
    end

    whitespace_re = /\s/
    if char =~ whitespace_re
      current += 1
      next
    end

    numbers_re = /[0-9]/
    if char =~ numbers_re
      value = ''
      while char =~ numbers_re
        value << char
        current += 1
        char = input[current]
      end
      tokens << { type: 'number', value: value }
      next
    end

    if char == '"'
      value = ''
      # skip the opening '"'
      current += 1
      char = current
      while char != '"'
        value << char
        current += 1
        char = input[current]
      end
      # skip the closing '"'
      current += 1
      char = input[current]
      tokens << { type: 'string', value: value }
      next
    end

    letters_re = /[a-zA-Z]/
    if char =~ letters_re
      value = '' 
      while char =~ letters_re
        value << char
        current += 1
        char = input[current]
      end
      tokens << { type: 'name', value: value }
      next
    end

    # if nothing matches, it's a syntax error
    raise StandardError.new("I don't know what char this is: #{char}")
  end

  tokens
end

# -------------------------------------------------------------------------------------------------
# [{:type=>"paren", :value=>"("},       | {:type=>"Program",
#  {:type=>"name", :value=>"add"},      |  :body=>
#  {:type=>"number", :value=>"2"},      |   [{:type=>"CallExpression",
#  {:type=>"paren", :value=>"("},       |     :name=>"add",
#  {:type=>"name", :value=>"subtract"}, |     :params=>
#  {:type=>"number", :value=>"4"},      |      [{:type=>"NumberLiteral", :value=>"2"},
#  {:type=>"number", :value=>"2"},      |       {:type=>"CallExpression",
#  {:type=>"paren", :value=>")"},       |        :name=>"subtract",
#  {:type=>"paren", :value=>")"}]       |        :params=>
#                                       |         [{:type=>"NumberLiteral", :value=>"4"},
#                                       |          {:type=>"NumberLiteral", :value=>"2"}]}]}]}
# -------------------------------------------------------------------------------------------------
def parse(tokens)
  current = 0

  walk = ->() do
    token = tokens[current]
    if token[:type] == "number"
      current += 1
      return { type: 'NumberLiteral', value: token[:value] }
    end
    if token[:type] == "string"
      current += 1
      return { type: 'StringLiteral', value: token[:value] }
    end
    if token[:type] == "paren" && token[:value] == "("
      # skip opening paren, we don't care about it in the AST
      current += 1
      token = tokens[current]
      node = { type: 'CallExpression', name: token[:value], params: [] }
      # skip the name token, go to the name token contents
      current += 1
      token = tokens[current]
      # loop/recurse the name token contents
      while (token[:type] != 'paren') || (token[:type] == 'paren' && token[:value] != ')')
        node[:params] << walk.call()
        token = tokens[current]
      end
      # skip closing paren
      current += 1

      return node
    end

    # on unrecognized token type, raise error
    raise StandardError.new("I don't know what token this is: #{token}")
  end

  ast = { type: 'Program', body: [] }
  # looping cause there may be expressions one after another, not just
  # nested expressions ->
  # (add 2 2)
  # (substract 4 2)
  while current < tokens.length
    ast[:body] << walk.call()
  end

  ast
end

def traverse(ast, visitor)
  traverse_node = ->(node, parent) do
    method = visitor[node[:type]]
    if method
      method.call(node, parent)
    end

    case node[:type]
    when 'Program'
      node[:body].each { |child| traverse_node.call(child, node) }
    when 'CallExpression'
      node[:params].each { |child| traverse_node.call(child, node) }
    when 'NumberLiteral', 'StringLiteral'
      nil
    else
      raise StandardError.new("I don't know what part of ast this is: #{node[:type]}")
    end
  end
  
  traverse_node.call(ast, nil)
end

# ---------------------------------------------------------------------------------------------------------------------
# {:type=>"Program",                                    | {:type=>"Program",
#  :body=>                                              |  :body=>
#   [{:type=>"CallExpression",                          |   [{:type=>"ExpressionStatement",
#     :name=>"add",                                     |     :expression=>
#     :params=>                                         |      {:type=>"CallExpression",
#      [{:type=>"NumberLiteral", :value=>"2"},          |       :callee=>{:type=>"Identifier", :name=>"add"},
#       {:type=>"CallExpression",                       |       :arguments=>
#        :name=>"subtract",                             |        [{:type=>"NumberLiteral", :value=>"2"},
#        :params=>                                      |         {:type=>"CallExpression",
#         [{:type=>"NumberLiteral", :value=>"4"},       |          :callee=>{:type=>"Identifier", :name=>"subtract"},
#          {:type=>"NumberLiteral", :value=>"2"}]}]}]}  |          :arguments=>
#                                                       |           [{:type=>"NumberLiteral", :value=>"4"},
#                                                       |            {:type=>"NumberLiteral", :value=>"2"}]}]}}]}
# ---------------------------------------------------------------------------------------------------------------------
def transform(ast)
  visitor = {
    "NumberLiteral" => ->(node, parent) {
      parent[:_context] << { type: 'NumberLiteral', value: node[:value] }
    },
    "StringLiteral" => ->(node, parent) {
      parent[:_context] << { type: 'StringLiteral', value: node[:value] }
    },
    "CallExpression" => ->(node, parent) {
      expression = { type: 'CallExpression', callee: { type: 'Identifier', name: node[:name] }, arguments: [] }
      node[:_context] = expression[:arguments]
      if parent[:type] != 'CallExpression'
        expression = { type: 'ExpressionStatement', expression: expression }
      end
      parent[:_context] << expression
    },
  }

  ast[:_context] = []
  traverse(ast, visitor)

  new_ast = { type: 'Program', body: ast[:_context] }
  new_ast 
end

def generate_code(node)
  case node[:type]
  when 'Program'
    return node[:body].map {|x| generate_code(x)}.join('\n')
  when 'ExpressionStatement'
    return generate_code(node[:expression]) + ";"
  when 'CallExpression'
    return generate_code(node[:callee]) + "(" + node[:arguments].map {|x| generate_code(x)}.join(', ') + ")"
  when 'Identifier'
    return node[:name]
  when 'NumberLiteral'
    return node[:value]
  when 'StringLiteral'
    return '"' + node[:value] + '"'
  else
    raise StandardError.new("I don't know what node type this is: #{node[:type]}")
  end
end

def main
  input = "(add 2 (subtract 4 2))"
  puts "Compiling..."
  puts "Input:  #{input}"

  tokenized = tokenize(input)
  parsed = parse(tokenized)
  transformed = transform(parsed)
  output = generate_code(transformed)

  puts "Output: #{output}"
end

main
