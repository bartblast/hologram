defmodule Hologram.Socket.DecoderTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Socket.Decoder

  test "top-level data" do
    assert decode([1, "__atom__:abc"]) == :abc
  end

  test "anonymous function" do
    assert decode(%{
             "type" => "anonymous_function",
             "capturedModule" => "Calendar.ISO",
             "capturedFunction" => "parse_date",
             "arity" => 2
           }) == (&Calendar.ISO.parse_date/2)
  end

  test "atom" do
    assert decode("__atom__:abc") == :abc
  end

  test "binary bitstring" do
    assert decode("__binary__:a\"bc") == "a\"bc"
  end

  test "non-binary bitstring" do
    assert decode(%{"type" => "bitstring", "bits" => [1, 0, 1, 0]}) == <<1::1, 0::1, 1::1, 0::1>>
  end

  describe "float" do
    test "float" do
      assert decode("__float__:1.23") === 1.23
    end

    test "integer" do
      assert decode("__float__:1") === 1.0
    end
  end

  test "integer" do
    assert decode("__integer__:123") == 123
  end

  test "list" do
    assert decode(%{
             "type" => "list",
             "data" => ["__integer__:1", "__float__:2.34"]
           }) == [1, 2.34]
  end

  test "map" do
    assert decode(%{
             "type" => "map",
             "data" => [
               ["__atom__:a", "__integer__:1"],
               ["__binary__:b", "__float__:2.34"]
             ]
           }) == %{:a => 1, "b" => 2.34}
  end

  test "pid" do
    assert decode(%{"type" => "pid", "segments" => [0, 11, 222]}) == pid("0.11.222")
  end

  test "port" do
    assert decode(%{"type" => "port", "value" => "0.11"}) == port("0.11")
  end

  test "reference" do
    assert decode(%{"type" => "reference", "value" => "0.1.2.3"}) == ref("0.1.2.3")
  end

  test "tuple" do
    assert decode(%{
             "type" => "tuple",
             "data" => ["__integer__:1", "__float__:2.34"]
           }) == {1, 2.34}
  end
end
