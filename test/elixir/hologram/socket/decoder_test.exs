defmodule Hologram.Socket.DecoderTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Socket.Decoder

  @delimiter delimiter()

  describe "version 2" do
    test "atom" do
      assert decode(2, "axyz") == :xyz
    end

    test "bitstring, empty" do
      assert decode(2, "b") == ""
    end

    test "bitstring, single-byte, without leftover bits" do
      assert decode(2, "b061") == "a"
    end

    test "bitstring, single-byte, with leftover bits" do
      assert decode(2, "b3a0") == <<5::size(3)>>
    end

    test "bitstring, multiple-byte, without leftover bits" do
      assert decode(2, "b0486f6c6f6772616d") == "Hologram"
    end

    test "bitstring, multiple-byte, with leftover bits" do
      assert decode(2, "b3616263a0") == <<97, 98, 99, 5::size(3)>>
    end

    test "float, encoded as float" do
      assert decode(2, "f1.23") === 1.23
    end

    test "float, encoded as integer" do
      assert decode(2, "f123") === 123.0
    end

    test "function capture" do
      data = "cCalendar.ISO#{@delimiter}parse_date#{@delimiter}2"
      assert decode(2, data) == (&Calendar.ISO.parse_date/2)
    end

    test "integer" do
      assert decode(2, "i123") == 123
    end

    test "list" do
      data = %{"t" => "l", "d" => ["i1", "f2.34"]}
      assert decode(2, data) == [1, 2.34]
    end

    test "map" do
      data = %{"t" => "m", "d" => [["ax", "i1"], ["b079", "f2.34"]]}
      assert decode(2, data) == %{:x => 1, "y" => 2.34}
    end

    test "pid" do
      data = "pmy_node@my_host#{@delimiter}0,11,222#{@delimiter}server"
      assert decode(2, data) == pid("0.11.222")
    end

    test "tuple" do
      data = %{"t" => "t", "d" => ["i1", "f2.34"]}
      assert decode(2, data) == {1, 2.34}
    end
  end

  describe "version 1" do
    test "atom" do
      assert decode(1, "__atom__:xyz") == :xyz
    end

    test "bitstring, binary" do
      assert decode(1, "__binary__:a\"bc") == "a\"bc"
    end

    test "bitstring, non-binary" do
      data = %{"type" => "bitstring", "bits" => [1, 0, 1, 0]}
      assert decode(1, data) == <<1::1, 0::1, 1::1, 0::1>>
    end

    test "float, encoded as float" do
      assert decode(1, "__float__:1.23") === 1.23
    end

    test "float, encoded as integer" do
      assert decode(1, "__float__:123") === 123.0
    end

    test "function capture" do
      data = %{
        "type" => "anonymous_function",
        "capturedModule" => "Calendar.ISO",
        "capturedFunction" => "parse_date",
        "arity" => 2
      }

      assert decode(1, data) == (&Calendar.ISO.parse_date/2)
    end

    test "integer" do
      assert decode(1, "__integer__:123") == 123
    end

    test "list" do
      data = %{
        "type" => "list",
        "data" => ["__integer__:1", "__float__:2.34"]
      }

      assert decode(1, data) == [1, 2.34]
    end

    test "map" do
      data = %{
        "type" => "map",
        "data" => [
          ["__atom__:a", "__integer__:1"],
          ["__binary__:b", "__float__:2.34"]
        ]
      }

      assert decode(1, data) == %{:a => 1, "b" => 2.34}
    end

    test "pid" do
      data = %{"type" => "pid", "segments" => [0, 11, 222]}
      assert decode(1, data) == pid("0.11.222")
    end

    test "tuple" do
      data = %{
        "type" => "tuple",
        "data" => ["__integer__:1", "__float__:2.34"]
      }

      assert decode(1, data) == {1, 2.34}
    end
  end

  #   describe "version 1" do
  #     test "top-level data" do
  #       assert decode([1, "__atom__:abc"]) == :abc
  #     end

  #     test "port" do
  #       assert decode(1, %{"type" => "port", "value" => "0.11"}) == port("0.11")
  #     end

  #     test "reference" do
  #       assert decode(1, %{"type" => "reference", "value" => "0.1.2.3"}) == ref("0.1.2.3")
  #     end
  #   end
end
