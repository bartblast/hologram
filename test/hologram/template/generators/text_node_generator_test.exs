defmodule Hologram.Template.TextNodeGeneratorTest do
  use Hologram.Test.UnitCase , async: true
  alias Hologram.Template.TextNodeGenerator

  test "generate/1" do
    content = "a'b\nc'd\ne&lcub;f&rcub;ga'b\nc'd\ne&lcub;f&rcub;g"
    expected_encoded_content = "a\\'b\\nc\\'d\\ne{f}ga\\'b\\nc\\'d\\ne{f}g"

    result = TextNodeGenerator.generate(content)
    expected = "{ type: 'text', content: '#{expected_encoded_content}' }"

    assert result == expected
  end
end
