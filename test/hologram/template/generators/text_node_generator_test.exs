defmodule Hologram.Template.TextNodeGeneratorTest do
  use Hologram.TestCase, async: true
  alias Hologram.Template.TextNodeGenerator

  test "generate/1" do
    text = "a'b\nc'd\ne"

    result = TextNodeGenerator.generate(text)
    expected = "{ type: 'text_node', text: 'a\\'b\\nc\\'d\\ne' }"

    assert result == expected
  end
end
