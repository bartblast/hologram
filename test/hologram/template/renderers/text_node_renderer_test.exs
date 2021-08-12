defmodule Hologram.Template.TextNodeRendererTest do
  use Hologram.TestCase, async: true

  alias Hologram.Template.Document.TextNode
  alias Hologram.Template.Renderer

  test "render/2" do
    content = "a&lcub;b&rcub;ca&lcub;b&rcub;c"
    text_node = %TextNode{content: content}

    result = Renderer.render(text_node, %{})

    expected = "a{b}ca{b}c"
    assert result == expected
  end
end
