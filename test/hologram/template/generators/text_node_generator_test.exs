defmodule Hologram.Template.TextNodeGeneratorTest do
  use Hologram.TestCase, async: true
  alias Hologram.Template.TextNodeGenerator

  test "generate/1" do
    content = "a'b\nc'd\ne"

    result = TextNodeGenerator.generate(content)
    expected = "{ type: 'text', content: 'a\\'b\\nc\\'d\\ne' }"

    assert result == expected
  end
end
