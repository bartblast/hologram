defmodule Hologram.Socket.DecoderTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Socket.Decoder

  test "atom" do
    assert decode(%{"type" => "atom", "value" => "__struct__"}) == :__struct__
  end

  test "binary" do
    assert decode("__binary__:a\"bc") == "a\"bc"
  end

  describe "float" do
    test "float" do
      assert decode(%{"type" => "float", "value" => 1.0}) === 1.0
    end

    test "integer" do
      assert decode(%{"type" => "float", "value" => 1}) === 1.0
    end
  end

  test "integer" do
    assert decode("__integer__:123") == 123
  end

  test "reference" do
    assert decode(%{"type" => "reference", "value" => "0.1.2.3"}) == ref("0.1.2.3")
  end
end
