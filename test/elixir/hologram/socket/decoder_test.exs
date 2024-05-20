defmodule Hologram.Socket.DecoderTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Socket.Decoder

  test "atom" do
    assert decode(%{"type" => "atom", "value" => "__struct__"}) == :__struct__
  end

  test "integer" do
    assert decode("__integer__:123") == 123
  end
end
