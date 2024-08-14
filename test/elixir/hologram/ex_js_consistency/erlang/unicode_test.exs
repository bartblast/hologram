defmodule Hologram.ExJsConsistency.Erlang.UnicodeTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/unicode_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.BitstringUtils, only: [to_bit_list: 1]

  @moduletag :consistency

  test "characters_to_binary/1" do
    assert :unicode.characters_to_binary("全息图") ==
             :unicode.characters_to_binary("全息图", :utf8, :utf8)
  end

  describe "characters_to_binary/3" do
    test "input is an empty list" do
      assert :unicode.characters_to_binary([], :utf8, :utf8) == <<>>
    end

    test "input is a list of ASCII code points" do
      input = [?a, ?b, ?c]
      result = :unicode.characters_to_binary(input, :utf8, :utf8)

      # Specified this way, because it's not possible to make the formatter ignore specific lines of code.
      bits =
        """
        [
          0, 1, 1, 0, 0, 0, 0, 1,
          0, 1, 1, 0, 0, 0, 1, 0,
          0, 1, 1, 0, 0, 0, 1, 1
        ]
        """
        |> Code.eval_string()
        |> elem(0)

      assert to_bit_list(result) == bits
    end

    test "input is a list of non-ASCII code points (Chinese)" do
      input = [?全, ?息, ?图]
      result = :unicode.characters_to_binary(input, :utf8, :utf8)

      # Specified this way, because it's not possible to make the formatter ignore specific lines of code.
      bits =
        """
        [          
          1, 1, 1, 0, 0, 1, 0, 1,
          1, 0, 0, 0, 0, 1, 0, 1,
          1, 0, 1, 0, 1, 0, 0, 0,
          1, 1, 1, 0, 0, 1, 1, 0,
          1, 0, 0, 0, 0, 0, 0, 1,
          1, 0, 1, 0, 1, 1, 1, 1,
          1, 1, 1, 0, 0, 1, 0, 1,
          1, 0, 0, 1, 1, 0, 1, 1,
          1, 0, 1, 1, 1, 1, 1, 0          
        ]
        """
        |> Code.eval_string()
        |> elem(0)

      assert to_bit_list(result) == bits
    end

    test "input is a binary bitstring" do
      input = <<"abc">>
      assert :unicode.characters_to_binary(input, :utf8, :utf8) == input
    end

    test "input is a non-binary bitstring" do
      input = <<1::1, 0::1, 1::1>>

      assert_error ArgumentError,
                   build_argument_error_msg(1, "not valid character data (an iodata term)"),
                   fn ->
                     :unicode.characters_to_binary(input, :utf8, :utf8)
                   end
    end

    test "input is a list of binary bitstrings" do
      input = [<<"abc">>, <<"def">>, <<"ghi">>]
      assert :unicode.characters_to_binary(input, :utf8, :utf8) == <<"abcdefghi">>
    end

    test "input is a list of non-binary bitstrings" do
      input = [
        <<1::1, 1::1, 0::1>>,
        <<1::1, 0::1, 1::1>>,
        <<0::1, 1::1, 1::1>>
      ]

      assert_error ArgumentError,
                   build_argument_error_msg(1, "not valid character data (an iodata term)"),
                   fn ->
                     :unicode.characters_to_binary(input, :utf8, :utf8)
                   end
    end

    test "input is a list of code points mixed with binary bitstrings" do
      input = [
        ?a,
        <<"bcd">>,
        ?e,
        <<"fgh">>,
        ?i
      ]

      assert :unicode.characters_to_binary(input, :utf8, :utf8) == <<"abcdefghi">>
    end

    test "input is a list of elements of types other than a list or a bitstring" do
      input = [123.45, :abc]

      assert_error ArgumentError,
                   build_argument_error_msg(1, "not valid character data (an iodata term)"),
                   fn ->
                     :unicode.characters_to_binary(input, :utf8, :utf8)
                   end
    end

    test "input is not a list or a bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not valid character data (an iodata term)"),
                   fn ->
                     :unicode.characters_to_binary(:abc, :utf8, :utf8)
                   end
    end

    test "input is a nested list" do
      input = [
        ?a,
        [
          ?b,
          [
            ?c,
            <<"def">>,
            ?g
          ],
          ?h
        ],
        ?i
      ]

      assert :unicode.characters_to_binary(input, :utf8, :utf8) == <<"abcdefghi">>
    end

    test "input contains invalid code points" do
      input = [
        ?a,
        <<"bcd">>,
        # Max Unicode code point value is 1,114,112
        1_114_113,
        <<"efg">>
      ]

      expected = {:error, <<"abcd">>, [1_114_113, <<"efg">>]}

      assert :unicode.characters_to_binary(input, :utf8, :utf8) == expected
    end
  end

  describe "characters_to_list/1" do
    test "UTF8 binary" do
      assert :unicode.characters_to_list("全息图") == [20_840, 24_687, 22_270]
    end

    test "list of UTF8 binaries" do
      assert :unicode.characters_to_list(["abc", "全息图", "xyz"]) == [
               97,
               98,
               99,
               20_840,
               24_687,
               22_270,
               120,
               121,
               122
             ]
    end
  end
end
