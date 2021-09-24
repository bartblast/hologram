defmodule Hologram.Template.NodeListGeneratorTest do
  use Hologram.Test.UnitCase , async: true

  alias Hologram.Template.Document.TextNode
  alias Hologram.Template.NodeListGenerator

  describe "generate/1" do
    test "non-empty" do
      nodes = [
        %TextNode{content: "test_1"},
        %TextNode{content: "test_2"}
      ]

      result = NodeListGenerator.generate(nodes)
      expected = "[ { type: 'text', content: 'test_1' }, { type: 'text', content: 'test_2' } ]"

      assert result == expected
    end

    test "empty" do
      assert NodeListGenerator.generate([]) == "[]"
    end
  end
end
