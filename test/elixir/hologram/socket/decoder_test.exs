defmodule Hologram.Socket.DecoderTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Socket.Decoder

  describe "version 2" do
    test "atom" do
      assert decode(2, "a:abc") == :abc
    end

    test "bitstring, empty" do
      assert decode(2, "b") == ""
    end

    test "bitstring, single-byte, without leftover bits" do
      assert decode(2, "b:61") == "a"
    end

    test "bitstring, single-byte, with leftover bits" do
      assert decode(2, "b:a0:3") == <<5::size(3)>>
    end

    test "bitstring, multiple-byte, without leftover bits" do
      assert decode(2, "b:486f6c6f6772616d") == "Hologram"
    end

    test "bitstring, multiple-byte, with leftover bits" do
      assert decode(2, "b:616263a0:3") == <<97, 98, 99, 5::size(3)>>
    end

    test "float, encoded as float" do
      assert decode(2, "f:1.23") === 1.23
    end

    test "float, encoded as integer" do
      assert decode(2, "f:1") === 1.0
    end

    test "integer" do
      assert decode(2, "i:123") == 123
    end
  end

  describe "version 1" do
    test "top-level data" do
      assert decode([1, "__atom__:abc"]) == :abc
    end

    test "anonymous function" do
      assert decode(1, %{
               "type" => "anonymous_function",
               "capturedModule" => "Calendar.ISO",
               "capturedFunction" => "parse_date",
               "arity" => 2
             }) == (&Calendar.ISO.parse_date/2)
    end

    test "atom" do
      assert decode(1, "__atom__:abc") == :abc
    end

    test "binary bitstring" do
      assert decode(1, "__binary__:a\"bc") == "a\"bc"
    end

    test "non-binary bitstring" do
      assert decode(1, %{"type" => "bitstring", "bits" => [1, 0, 1, 0]}) ==
               <<1::1, 0::1, 1::1, 0::1>>
    end

    test "float, encoded as float" do
      assert decode(1, "__float__:1.23") === 1.23
    end

    test "float, encoded as integer" do
      assert decode(1, "__float__:1") === 1.0
    end

    test "integer" do
      assert decode(1, "__integer__:123") == 123
    end

    test "list" do
      assert decode(1, %{
               "type" => "list",
               "data" => ["__integer__:1", "__float__:2.34"]
             }) == [1, 2.34]
    end

    test "map" do
      assert decode(1, %{
               "type" => "map",
               "data" => [
                 ["__atom__:a", "__integer__:1"],
                 ["__binary__:b", "__float__:2.34"]
               ]
             }) == %{:a => 1, "b" => 2.34}
    end

    test "pid" do
      assert decode(1, %{"type" => "pid", "segments" => [0, 11, 222]}) == pid("0.11.222")
    end

    test "port" do
      assert decode(1, %{"type" => "port", "value" => "0.11"}) == port("0.11")
    end

    test "reference" do
      assert decode(1, %{"type" => "reference", "value" => "0.1.2.3"}) == ref("0.1.2.3")
    end

    test "tuple" do
      assert decode(1, %{
               "type" => "tuple",
               "data" => ["__integer__:1", "__float__:2.34"]
             }) == {1, 2.34}
    end
  end
end
