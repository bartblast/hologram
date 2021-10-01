defmodule Hologram.Template.TextNodeEncoderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Template.Document.TextNode
  alias Hologram.Template.Encoder

  test "encode/1" do
    text_node = %TextNode{content: "a'b\nc'd\ne&lcub;f&rcub;ga'b\nc'd\ne&lcub;f&rcub;g"}
    expected_encoded_content = "a\\'b\\nc\\'d\\ne{f}ga\\'b\\nc\\'d\\ne{f}g"

    result = Encoder.encode(text_node)
    expected = "{ type: 'text', content: '#{expected_encoded_content}' }"

    assert result == expected
  end
end
