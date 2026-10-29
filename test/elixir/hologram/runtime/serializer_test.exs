defmodule Hologram.Runtime.SerializerTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Runtime.Serializer

  alias Hologram.Compiler.Encoder
  alias Hologram.Runtime.Deserializer

  @delimiter Deserializer.delimiter()

  defp captured_function(value), do: value

  # A map serializes its entries in the order it iterates them, and atom keys iterate in the order
  # of the atom table rather than anything the test controls, so maps are compared with their
  # entries sorted.
  defp decode_sorting_map_entries(json) do
    json
    |> Jason.decode!()
    |> sort_map_entries()
  end

  defp sort_map_entries(%{"t" => "m", "d" => entries}) do
    sorted_entries =
      entries
      |> Enum.map(&sort_map_entries/1)
      |> Enum.sort()

    %{"t" => "m", "d" => sorted_entries}
  end

  defp sort_map_entries(%{"t" => type, "d" => items}) do
    %{"t" => type, "d" => Enum.map(items, &sort_map_entries/1)}
  end

  defp sort_map_entries(items) when is_list(items) do
    Enum.map(items, &sort_map_entries/1)
  end

  defp sort_map_entries(value), do: value

  describe "serialize/1" do
    test "a term the format can carry" do
      assert serialize(:abc) == {:ok, ~s'[4,"aabc"]'}
    end

    test "an anonymous function" do
      assert serialize(fn x -> x end) ==
               {:error, "term contains a function that is not a named function capture"}
    end

    test "an improper list" do
      assert serialize([1 | 2]) == {:error, "term contains an improper list"}
    end
  end

  describe "serialize!/1" do
    test "atom" do
      assert serialize!(:abc) == ~s'[4,"aabc"]'
    end

    test "atom, alias" do
      assert serialize!(Calendar.ISO) == ~s'[4,"aElixir.Calendar.ISO"]'
    end

    test "atom, boolean" do
      assert serialize!(true) == ~s'[4,"atrue"]'
    end

    test "atom, nil" do
      assert serialize!(nil) == ~s'[4,"anil"]'
    end

    test "bitstring, single-byte, without leftover bits" do
      assert serialize!(<<255>>) == ~s'[4,"b0ff"]'
    end

    test "bitstring, single-byte, with leftover bits" do
      assert serialize!(<<5::size(3)>>) == ~s'[4,"b3a0"]'
    end

    test "bitstring, multiple-byte, without leftover bits" do
      assert serialize!(<<255, 254>>) == ~s'[4,"b0fffe"]'
    end

    test "bitstring, multiple-byte, with leftover bits" do
      assert serialize!(<<97, 98, 99, 5::size(3)>>) == ~s'[4,"b3616263a0"]'
    end

    test "bitstring, UTF-8 encoded surrogate" do
      assert serialize!(<<0xED, 0xA0, 0x80>>) == ~s'[4,"b0eda080"]'
    end

    test "float" do
      assert serialize!(1.23) == ~s'[4,"f1.23"]'
    end

    test "float, negative" do
      assert serialize!(-2.5) == ~s'[4,"f-2.5"]'
    end

    test "function capture, Elixir module" do
      assert serialize!(&Calendar.ISO.parse_date/2) ==
               ~s'[4,"cCalendar.ISO#{@delimiter}parse_date#{@delimiter}2"]'
    end

    test "function capture, Erlang module" do
      assert serialize!(&:lists.reverse/1) ==
               ~s'[4,"c:lists#{@delimiter}reverse#{@delimiter}1"]'
    end

    test "function capture, local" do
      assert serialize!(&captured_function/1) ==
               ~s'[4,"cHologram.Runtime.SerializerTest#{@delimiter}captured_function#{@delimiter}1"]'
    end

    test "integer" do
      assert serialize!(123) == ~s'[4,"i123"]'
    end

    test "integer, negative" do
      assert serialize!(-123) == ~s'[4,"i-123"]'
    end

    test "integer, beyond 64 bits" do
      assert serialize!(1_180_591_620_717_411_303_424) == ~s'[4,"i1180591620717411303424"]'
    end

    test "list" do
      assert serialize!([1, :abc]) == ~s'[4,{"t":"l","d":["i1","aabc"]}]'
    end

    test "list, empty" do
      assert serialize!([]) == ~s'[4,{"t":"l","d":[]}]'
    end

    test "list, nested" do
      assert serialize!([1, [2]]) == ~s'[4,{"t":"l","d":["i1",{"t":"l","d":["i2"]}]}]'
    end

    test "map" do
      assert serialize!(%{abc: 1}) == ~s'[4,{"t":"m","d":[["aabc","i1"]]}]'
    end

    test "map, empty" do
      assert serialize!(%{}) == ~s'[4,{"t":"m","d":[]}]'
    end

    # An atom key comes before a binary key in a map's own order, so the order is fixed here.
    test "map, multiple entries" do
      assert serialize!(%{:abc => 1, "xyz" => 2.5}) ==
               ~s'[4,{"t":"m","d":[["aabc","i1"],["sxyz","f2.5"]]}]'
    end

    test "pid" do
      assert serialize!(pid("0.11.222")) ==
               ~s'[4,"pnonode@nohost#{@delimiter}0,11,222#{@delimiter}server"]'
    end

    test "port" do
      assert serialize!(port("0.11")) ==
               ~s'[4,"ononode@nohost#{@delimiter}0,11#{@delimiter}server"]'
    end

    test "reference" do
      assert serialize!(ref("0.1.2.3")) ==
               ~s'[4,{"t":"r","n":"jnonode@nohost","c":0,"i":[3,2,1]}]'
    end

    test "Regex struct" do
      regex = ~r/ab/i

      {:re_pattern, capture_count, unicode, crlf, re_pattern_ref} = regex.re_pattern

      {node_str, creation, id_words} =
        re_pattern_ref
        |> :erlang.term_to_binary()
        |> Encoder.parse_reference_binary()

      serialized_re_pattern_ref = %{
        "t" => "r",
        "n" => "j#{node_str}",
        "c" => creation,
        "i" => id_words
      }

      serialized_re_pattern = %{
        "t" => "t",
        "d" => [
          "are_pattern",
          "i#{capture_count}",
          "i#{unicode}",
          "i#{crlf}",
          serialized_re_pattern_ref
        ]
      }

      json = serialize!(regex)

      assert decode_sorting_map_entries(json) == [
               4,
               %{
                 "t" => "m",
                 "d" => [
                   ["a__struct__", "aElixir.Regex"],
                   ["aopts", %{"t" => "l", "d" => ["acaseless"]}],
                   ["are_pattern", serialized_re_pattern],
                   ["asource", "sab"]
                 ]
               }
             ]
    end

    test "string" do
      assert serialize!("Hologram") == ~s'[4,"sHologram"]'
    end

    test "string, empty" do
      assert serialize!("") == ~s'[4,"s"]'
    end

    test "string, beyond ASCII" do
      assert serialize!("zażółć 🎉") == ~s'[4,"szażółć 🎉"]'
    end

    test "string, characters JSON escapes" do
      assert serialize!(~s'say "hi"\n') == ~S'[4,"ssay \"hi\"\n"]'
    end

    test "struct" do
      json = serialize!(%Version{major: 1, minor: 2, patch: 3, pre: [], build: nil})

      assert decode_sorting_map_entries(json) == [
               4,
               %{
                 "t" => "m",
                 "d" => [
                   ["a__struct__", "aElixir.Version"],
                   ["abuild", "anil"],
                   ["amajor", "i1"],
                   ["aminor", "i2"],
                   ["apatch", "i3"],
                   ["apre", %{"t" => "l", "d" => []}]
                 ]
               }
             ]
    end

    test "tuple" do
      assert serialize!({1, :abc}) == ~s'[4,{"t":"t","d":["i1","aabc"]}]'
    end

    test "tuple, empty" do
      assert serialize!({}) == ~s'[4,{"t":"t","d":[]}]'
    end

    test "reads back as the same term through the server deserializer" do
      term = %{
        bitstrings: [<<255>>, <<5::size(3)>>],
        capture: &Calendar.ISO.parse_date/2,
        identifiers: {pid("0.11.222"), port("0.11"), ref("0.1.2.3")},
        numbers: [1, -2.5, 1_180_591_620_717_411_303_424],
        strings: ["", "Hologram", "zażółć 🎉", ~s'say "hi"\n'],
        values: [:abc, nil, true, {}, [], %{}]
      }

      json = serialize!(term)

      assert Deserializer.deserialize(json) == term
    end

    test "anonymous function" do
      assert_error ArgumentError,
                   "term contains a function that is not a named function capture",
                   fn -> serialize!(fn x -> x end) end
    end

    test "improper list" do
      assert_error ArgumentError, "term contains an improper list", fn ->
        serialize!([1, 2 | 3])
      end
    end
  end
end
