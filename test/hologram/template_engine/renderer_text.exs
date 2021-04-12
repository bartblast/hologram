defmodule Hologram.TemplateEngine.RendererTest do
  use ExUnit.Case, async: true

  alias Hologram.TemplateEngine.AST.TextNode
  alias Hologram.TemplateEngine.Renderer

  test "text node" do
    ast = %TextNode{text: "test"}

    result = Renderer.render(ast, %{})
    expected = "test"

    assert result == expected
  end
end
