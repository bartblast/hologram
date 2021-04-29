defmodule Hologram.TemplateEngine.IRGeneratorTest do
  use ExUnit.Case, async: true

  alias Hologram.TemplateEngine.AST.TextNode
  alias Hologram.TemplateEngine.IRGenerator

  test "text node" do
    ast = %TextNode{text: "test"}

    result = IRGenerator.generate(ast)
    expected = "{ type: 'text_node', text: 'test' }"

    assert result == expected
  end
end
