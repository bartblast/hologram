defmodule Hologram.Compiler.DecoderTest do
  use Hologram.TestCase, async: true
  alias Hologram.Compiler.Decoder

  test "string" do
    input = %{"type" => "string", "value" => "test"}
    assert Decoder.decode(input) == "test"
  end
end
