defmodule Hologram.Template.TextNodeRendererTest do
  use Hologram.TestCase, async: true

  alias Hologram.Template.Document.TextNode
  alias Hologram.Template.Renderer

  test "render/2" do
    content = "test_content"
    text_node = %TextNode{content: content}
    result = Renderer.render(text_node, %{})

    assert result == content
  end
end
