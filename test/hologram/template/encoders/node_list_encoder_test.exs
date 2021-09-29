defmodule Hologram.Template.NodeListEncoderTest do
  use Hologram.Test.UnitCase , async: true

  alias Hologram.Template.Document.TextNode
  alias Hologram.Template.Encoder

  describe "encode/1" do
    test "non-empty" do
      nodes = [
        %TextNode{content: "test_1"},
        %TextNode{content: "test_2"}
      ]

      result = Encoder.encode(nodes)
      expected = "[ { type: 'text', content: 'test_1' }, { type: 'text', content: 'test_2' } ]"

      assert result == expected
    end

    test "empty" do
      assert Encoder.encode([]) == "[]"
    end
  end
end
