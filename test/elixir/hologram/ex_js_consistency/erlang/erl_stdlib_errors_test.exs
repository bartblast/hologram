defmodule Hologram.ExJsConsistency.Erlang.ErlStdlibErrorsTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/erl_stdlib_errors_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  @badopt_error_info [error_info: %{cause: :badopt, module: :erl_stdlib_errors}]
  @error_info [error_info: %{module: :erl_stdlib_errors}]

  describe "format_error/2" do
    test "returns an empty map when the module has no formatter" do
      stacktrace = [{:some_module, :f, [1], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{}
    end

    test "returns an empty map when the frame carries no error_info" do
      stacktrace = [{:some_module, :f, [1], []}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{}
    end

    test "consults only the first stacktrace frame" do
      stacktrace = [
        {:some_module, :f, [1], @error_info},
        {:maps, :get, [:a, :b], @error_info}
      ]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{}
    end

    test "binary at: bad position" do
      stacktrace = [{:binary, :at, ["abc", :x], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{2 => "not an integer"}
    end

    test "binary at: negative position" do
      stacktrace = [{:binary, :at, ["abc", -1], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{2 => "out of range"}
    end

    test "binary at: bitstring subject" do
      stacktrace = [{:binary, :at, [<<1::1>>, 0], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "is a bitstring (expected a binary)"
             }
    end

    test "binary at: valid arguments produce no fragments" do
      stacktrace = [{:binary, :at, ["abc", 10], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{}
    end

    test "binary compile_pattern: not a valid pattern" do
      stacktrace = [{:binary, :compile_pattern, [""], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a valid pattern"
             }
    end

    test "binary copy: bad subject and count" do
      stacktrace = [{:binary, :copy, [:x, -1], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a binary",
               2 => "out of range"
             }
    end

    test "binary first: empty binary" do
      stacktrace = [{:binary, :first, [""], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "a zero-sized binary is not allowed"
             }
    end

    test "binary first: not a binary" do
      stacktrace = [{:binary, :first, [:x], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{1 => "not a binary"}
    end

    test "binary last: empty binary" do
      stacktrace = [{:binary, :last, [""], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "a zero-sized binary is not allowed"
             }
    end

    test "binary match/2: bad subject and pattern" do
      stacktrace = [{:binary, :match, [:x, :y], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a binary",
               2 => "not a valid pattern"
             }
    end

    test "binary match/2: empty binary pattern" do
      stacktrace = [{:binary, :match, ["abc", ""], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               2 => "not a valid pattern"
             }
    end

    test "binary match/2: compiled pattern is valid" do
      compiled_pattern = :binary.compile_pattern("b")
      stacktrace = [{:binary, :match, ["abc", compiled_pattern], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{}
    end

    test "binary match/3: scope not wholly inside binary" do
      stacktrace = [{:binary, :match, ["abc", "b", [scope: {0, 10}]], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               3 => "specified part is not wholly inside binary"
             }
    end

    test "binary match/3: bad options" do
      stacktrace = [{:binary, :match, ["abc", "b", [:x]], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{3 => "invalid options"}
    end

    test "binary matches: delegates to the match clauses" do
      stacktrace = [{:binary, :matches, ["abc", ""], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               2 => "not a valid pattern"
             }
    end

    test "binary replace/3: bad replacement" do
      stacktrace = [{:binary, :replace, ["abc", "b", :x], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               3 => "not a valid replacement"
             }
    end

    test "binary replace/4: badopt cause adds the options fragment" do
      stacktrace = [{:binary, :replace, ["abc", "b", "x", [:y]], @badopt_error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{4 => "invalid options"}
    end

    test "binary replace/4: bad replacement with badopt cause" do
      stacktrace = [{:binary, :replace, ["abc", "b", :x, [:y]], @badopt_error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               3 => "not a valid replacement",
               4 => "invalid options"
             }
    end

    test "binary replace/4: valid arguments without cause blame the options" do
      stacktrace = [{:binary, :replace, ["abc", "b", "x", [:y]], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{4 => "invalid options"}
    end

    test "binary split/2: bad pattern" do
      stacktrace = [{:binary, :split, ["abc", :x], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               2 => "not a valid pattern"
             }
    end

    test "binary split/3: bad options" do
      stacktrace = [{:binary, :split, ["abc", "b", [:x]], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{3 => "invalid options"}
    end

    test "lists keyfind: bad position" do
      stacktrace = [{:lists, :keyfind, [:k, :bad, [k: 1]], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{2 => "not an integer"}
    end

    test "lists keyfind: position out of range" do
      stacktrace = [{:lists, :keyfind, [:k, 0, [k: 1]], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{2 => "out of range"}
    end

    test "lists keyfind: not a list" do
      stacktrace = [{:lists, :keyfind, [:k, 1, :bad], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{3 => "not a list"}
    end

    test "lists keyfind: improper list" do
      stacktrace = [{:lists, :keyfind, [:k, 1, [{:k, 1} | :tail]], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{3 => "not a proper list"}
    end

    test "lists keyfind: bad position and bad list" do
      stacktrace = [{:lists, :keyfind, [:k, 0, :bad], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               2 => "out of range",
               3 => "not a list"
             }
    end

    test "lists keymember delegates to the keyfind clause" do
      stacktrace = [{:lists, :keymember, [:k, :bad, [k: 1]], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{2 => "not an integer"}
    end

    test "lists keysearch delegates to the keyfind clause" do
      stacktrace = [{:lists, :keysearch, [:k, :bad, [k: 1]], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{2 => "not an integer"}
    end

    test "lists member: not a list" do
      stacktrace = [{:lists, :member, [1, :bad], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{2 => "not a list"}
    end

    test "lists member: improper list" do
      stacktrace = [{:lists, :member, [5, [1 | 2]], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{2 => "not a proper list"}
    end

    test "lists reverse: not a list" do
      stacktrace = [{:lists, :reverse, [:bad, []], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{1 => "not a list"}
    end

    test "lists reverse: improper list" do
      stacktrace = [{:lists, :reverse, [[1 | 2], []], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{1 => "not a proper list"}
    end

    test "lists seq: non-integer arguments" do
      stacktrace = [{:lists, :seq, [:a, :b, :c], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not an integer",
               2 => "not an integer",
               3 => "not an integer"
             }
    end

    test "lists seq: zero increment" do
      stacktrace = [{:lists, :seq, [1, 10, 0], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               3 => "not a positive increment"
             }
    end

    test "lists seq: wrong positive increment" do
      stacktrace = [{:lists, :seq, [10, 1, 1], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               3 => "not a negative increment"
             }
    end

    test "lists seq: wrong negative increment" do
      stacktrace = [{:lists, :seq, [1, 10, -1], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               3 => "not a positive increment"
             }
    end

    test "maps find: not a map" do
      stacktrace = [{:maps, :find, [:a, :b], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{2 => "not a map"}
    end

    test "maps fold: bad fun and bad collection" do
      stacktrace = [{:maps, :fold, [:a, :b, :c], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a fun that takes three arguments",
               3 => "not a map or an iterator"
             }
    end

    test "maps fold: valid fun and iterator skip their fragments" do
      fun = fn acc, _key, _value -> acc end
      stacktrace = [{:maps, :fold, [fun, :b, [0 | %{a: 1}]], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{}
    end

    test "maps fold: iterator validity is checked recursively" do
      fun = fn acc, _key, _value -> acc end
      stacktrace = [{:maps, :fold, [fun, :b, {1, 2, 3}], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               3 => "not a map or an iterator"
             }
    end

    test "maps from_keys: improper list" do
      stacktrace = [{:maps, :from_keys, [[1 | 2], :a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{1 => "not a proper list"}
    end

    test "maps from_list: not a list" do
      stacktrace = [{:maps, :from_list, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{1 => "not a list"}
    end

    test "maps get/2: key not present in map" do
      stacktrace = [{:maps, :get, [:a, %{b: 2}], @error_info}]

      assert :erl_stdlib_errors.format_error(:badkey, stacktrace) == %{1 => "not present in map"}
    end

    test "maps get/2: not a map" do
      stacktrace = [{:maps, :get, [:a, :b], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{2 => "not a map"}
    end

    test "maps get/3: not a map" do
      stacktrace = [{:maps, :get, [:a, :b, :c], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{2 => "not a map"}
    end

    test "maps intersect: both arguments not maps" do
      stacktrace = [{:maps, :intersect, [:a, :b], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a map",
               2 => "not a map"
             }
    end

    test "maps intersect_with: bad fun and bad maps" do
      stacktrace = [{:maps, :intersect_with, [:a, :b, :c], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a fun that takes three arguments",
               2 => "not a map",
               3 => "not a map"
             }
    end

    test "maps is_key: not a map" do
      stacktrace = [{:maps, :is_key, [:a, :b], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{2 => "not a map"}
    end

    test "maps iterator: not a map" do
      stacktrace = [{:maps, :iterator, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{1 => "not a map"}
    end

    test "maps keys: not a map" do
      stacktrace = [{:maps, :keys, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{1 => "not a map"}
    end

    test "maps map: bad fun and bad collection" do
      stacktrace = [{:maps, :map, [:a, :b], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a fun that takes two arguments",
               2 => "not a map or an iterator"
             }
    end

    test "maps merge: both arguments not maps" do
      stacktrace = [{:maps, :merge, [:a, :b], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a map",
               2 => "not a map"
             }
    end

    test "maps merge_with: bad fun and bad maps" do
      stacktrace = [{:maps, :merge_with, [:a, :b, :c], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a fun that takes three arguments",
               2 => "not a map",
               3 => "not a map"
             }
    end

    test "maps next: bad iterator" do
      stacktrace = [{:maps, :next, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a valid iterator"
             }
    end

    test "maps put: not a map" do
      stacktrace = [{:maps, :put, [:a, :b, :c], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{3 => "not a map"}
    end

    test "maps remove: not a map" do
      stacktrace = [{:maps, :remove, [:a, :b], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{2 => "not a map"}
    end

    test "maps take: not a map" do
      stacktrace = [{:maps, :take, [:a, :b], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{2 => "not a map"}
    end

    test "maps to_list: not a map or iterator" do
      stacktrace = [{:maps, :to_list, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a map or an iterator"
             }
    end

    test "maps update: key not present in map" do
      stacktrace = [{:maps, :update, [:a, 1, %{b: 2}], @error_info}]

      assert :erl_stdlib_errors.format_error(:badkey, stacktrace) == %{
               1 => "not present in map"
             }
    end

    test "maps update: not a map" do
      stacktrace = [{:maps, :update, [:a, 1, :b], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{3 => "not a map"}
    end

    test "maps values: not a map" do
      stacktrace = [{:maps, :values, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{1 => "not a map"}
    end

    test "math ceil: not a number" do
      stacktrace = [{:math, :ceil, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{1 => "not a number"}
    end

    test "math log: domain error" do
      stacktrace = [{:math, :log, [0], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "is outside the domain for this function"
             }
    end

    test "math log: not a number" do
      stacktrace = [{:math, :log, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{1 => "not a number"}
    end

    test "math pow: both arguments not numbers" do
      stacktrace = [{:math, :pow, [:a, :b], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a number",
               2 => "not a number"
             }
    end

    test "math pow: valid number skips its fragment" do
      stacktrace = [{:math, :pow, [7, :a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{2 => "not a number"}
    end

    test "math unknown functions fall to the argument-count clauses" do
      stacktrace = [{:math, :unknown, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{1 => "not a number"}
    end

    test "re compile/1: not an iodata term" do
      stacktrace = [{:re, :compile, [:abc], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not an iodata term"
             }
    end

    test "re compile/2: parse-error pattern" do
      stacktrace = [{:re, :compile, ["a(", []], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 =>
                 "could not parse regular expression\nmissing closing parenthesis on character 2"
             }
    end

    test "re compile/2: valid pattern with badopt cause" do
      stacktrace = [{:re, :compile, ["abc", [:bad]], @badopt_error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{2 => "invalid options"}
    end

    test "re compile/2: parse-error pattern with badopt cause" do
      stacktrace = [{:re, :compile, ["a(", [:bad]], @badopt_error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 =>
                 "could not parse regular expression\nmissing closing parenthesis on character 2",
               2 => "invalid options"
             }
    end

    test "re compile/2: non-iodata pattern with badopt cause" do
      stacktrace = [{:re, :compile, [:abc, [:bad]], @badopt_error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not an iodata term",
               2 => "invalid options"
             }
    end

    test "re import: not an exported regular expression" do
      stacktrace = [{:re, :import, [:abc], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not an exported regular expression"
             }
    end

    test "re inspect: not a compiled regular expression" do
      stacktrace = [{:re, :inspect, [:abc, :namelist], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a compiled regular expression"
             }
    end

    test "re inspect: bad item" do
      {:ok, compiled_pattern} = :re.compile("a")
      stacktrace = [{:re, :inspect, [compiled_pattern, :bad_item], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{2 => "not a valid item"}
    end

    test "re inspect: non-atom item with a non-compiled first argument" do
      stacktrace = [{:re, :inspect, [:abc, "namelist"], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a compiled regular expression",
               2 => "not a valid item"
             }
    end

    test "re run/2: bad subject and pattern" do
      stacktrace = [{:re, :run, [:abc, :bad], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not an iodata term",
               2 => "neither an iodata term nor a compiled regular expression"
             }
    end

    test "re run/2: parse-error pattern" do
      stacktrace = [{:re, :run, ["abc", "a("], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               2 =>
                 "could not parse regular expression\nmissing closing parenthesis on character 2"
             }
    end

    test "re run/2: compiled pattern is valid" do
      {:ok, compiled_pattern} = :re.compile("a")
      stacktrace = [{:re, :run, ["abc", compiled_pattern], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{}
    end

    test "re run/2: fake compiled pattern tuple" do
      fake_pattern = {:re_pattern, 0, 0, 0, :fake}
      stacktrace = [{:re, :run, ["abc", fake_pattern], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               2 => "neither an iodata term nor a compiled regular expression"
             }
    end

    test "re run/2: improper iolist subject with binary tail is valid" do
      stacktrace = [{:re, :run, [[97 | "b"], "a"], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{}
    end

    test "re run/2: improper iolist subject with non-binary tail" do
      stacktrace = [{:re, :run, [[97 | 98], "a"], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not an iodata term"
             }
    end

    test "re run/2: iolist subject with out-of-range integer" do
      stacktrace = [{:re, :run, [[256], "a"], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not an iodata term"
             }
    end

    test "re run/3: valid arguments with badopt cause" do
      stacktrace = [{:re, :run, ["abc", "a", [:bad]], @badopt_error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{3 => "invalid options"}
    end

    test "re run/3: bad subject and pattern with badopt cause" do
      stacktrace = [{:re, :run, [:abc, :bad, [:x]], @badopt_error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not an iodata term",
               2 => "neither an iodata term nor a compiled regular expression",
               3 => "invalid options"
             }
    end

    test "re run/3: valid arguments produce no fragments" do
      stacktrace = [{:re, :run, ["abc", "a", [:caseless]], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{}
    end

    test "unicode characters_to_binary/1: bad chardata" do
      stacktrace = [{:unicode, :characters_to_binary, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not valid character data (an iodata term)"
             }
    end

    test "unicode characters_to_binary/2: bad chardata and encoding" do
      stacktrace = [{:unicode, :characters_to_binary, [:a, :foo], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not valid character data (an iodata term)",
               2 => "not a valid encoding"
             }
    end

    test "unicode characters_to_binary/3: bad chardata with valid encodings" do
      stacktrace = [{:unicode, :characters_to_binary, [:a, :utf8, :utf8], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not valid character data (an iodata term)"
             }
    end

    test "unicode characters_to_binary/3: bad encodings" do
      stacktrace = [{:unicode, :characters_to_binary, ["abc", :foo, :bar], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               2 => "not a valid encoding",
               3 => "not a valid encoding"
             }
    end

    test "unicode characters_to_binary/3: endianness tuple encodings are valid" do
      stacktrace = [
        {:unicode, :characters_to_binary, ["abc", {:utf16, :big}, {:utf32, :little}], @error_info}
      ]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{}
    end

    test "unicode characters_to_binary/3: latin1 and unicode encodings are valid" do
      stacktrace = [{:unicode, :characters_to_binary, ["abc", :latin1, :unicode], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{}
    end

    test "unicode characters_to_list delegates to the characters_to_binary clauses" do
      stacktrace = [{:unicode, :characters_to_list, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not valid character data (an iodata term)"
             }
    end

    test "unicode characters_to_nfc_binary: bad chardata" do
      stacktrace = [{:unicode, :characters_to_nfc_binary, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not valid character data (an iodata term)"
             }
    end

    test "unicode characters_to_nfc_list: bad chardata" do
      stacktrace = [{:unicode, :characters_to_nfc_list, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not valid character data (an iodata term)"
             }
    end

    test "unicode characters_to_nfd_binary: bad chardata" do
      stacktrace = [{:unicode, :characters_to_nfd_binary, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not valid character data (an iodata term)"
             }
    end

    test "unicode characters_to_nfd_list: bad chardata" do
      stacktrace = [{:unicode, :characters_to_nfd_list, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not valid character data (an iodata term)"
             }
    end

    test "unicode characters_to_nfkc_binary: bad chardata" do
      stacktrace = [{:unicode, :characters_to_nfkc_binary, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not valid character data (an iodata term)"
             }
    end

    test "unicode characters_to_nfkc_list: bad chardata" do
      stacktrace = [{:unicode, :characters_to_nfkc_list, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not valid character data (an iodata term)"
             }
    end

    test "unicode characters_to_nfkd_binary: bad chardata" do
      stacktrace = [{:unicode, :characters_to_nfkd_binary, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not valid character data (an iodata term)"
             }
    end

    test "unicode characters_to_nfkd_list: bad chardata" do
      stacktrace = [{:unicode, :characters_to_nfkd_list, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not valid character data (an iodata term)"
             }
    end

    test "raises FunctionClauseError when the stacktrace is empty" do
      stacktrace = []

      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":erl_stdlib_errors.format_error/2", [
                     :badarg,
                     stacktrace
                   ]),
                   {:erl_stdlib_errors, :format_error, [:badarg, stacktrace]}
    end

    test "raises FunctionClauseError when the top frame is not a 4-tuple" do
      fun = fn -> :ok end
      stacktrace = [{fun, [1], @error_info}]

      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":erl_stdlib_errors.format_error/2", [
                     :badarg,
                     stacktrace
                   ]),
                   {:erl_stdlib_errors, :format_error, [:badarg, stacktrace]}
    end

    test "raises FunctionClauseError when a binary clause needs args but the frame carries an arity" do
      stacktrace = [{:binary, :at, 2, @error_info}]

      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":erl_stdlib_errors.format_binary_error/3", [
                     :at,
                     2,
                     :none
                   ]),
                   {:erl_stdlib_errors, :format_error, [:badarg, stacktrace]}
    end

    test "raises FunctionClauseError when matches delegates a frame that carries an arity" do
      stacktrace = [{:binary, :matches, 2, @error_info}]

      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":erl_stdlib_errors.format_binary_error/3", [
                     :match,
                     2,
                     :none
                   ]),
                   {:erl_stdlib_errors, :format_error, [:badarg, stacktrace]}
    end

    test "raises FunctionClauseError for an unknown lists function" do
      expected_msg =
        build_function_clause_error_msg(":erl_stdlib_errors.format_lists_error/2", [
          :zip,
          [[], []]
        ])

      assert_error FunctionClauseError, expected_msg, fn ->
        :erl_stdlib_errors.format_error(:badarg, [{:lists, :zip, [[], []], @error_info}])
      end
    end

    test "raises FunctionClauseError when a lists clause needs args but the frame carries an arity" do
      expected_msg =
        build_function_clause_error_msg(":erl_stdlib_errors.format_lists_error/2", [:keyfind, 3])

      assert_error FunctionClauseError, expected_msg, fn ->
        :erl_stdlib_errors.format_error(:badarg, [{:lists, :keyfind, 3, @error_info}])
      end
    end

    test "raises FunctionClauseError when a maps clause needs args but the frame carries an arity" do
      stacktrace = [{:maps, :get, 2, @error_info}]

      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":erl_stdlib_errors.format_maps_error/2", [
                     :get,
                     2
                   ]),
                   {:erl_stdlib_errors, :format_error, [:badarg, stacktrace]}
    end

    test "raises FunctionClauseError when a math clause needs args but the frame carries an arity" do
      stacktrace = [{:math, :ceil, 1, @error_info}]

      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":erl_stdlib_errors.format_math_error/2", [
                     :ceil,
                     1
                   ]),
                   {:erl_stdlib_errors, :format_error, [:badarg, stacktrace]}
    end

    test "raises FunctionClauseError when a math domain-error clause needs args but the frame carries an arity" do
      stacktrace = [{:math, :log, 1, @error_info}]

      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":erl_stdlib_errors.maybe_domain_error/1", [1]),
                   {:erl_stdlib_errors, :format_error, [:badarg, stacktrace]}
    end

    test "raises FunctionClauseError for an unknown re function" do
      stacktrace = [{:re, :version, [], @error_info}]

      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":erl_stdlib_errors.format_re_error/3", [
                     :version,
                     [],
                     :none
                   ]),
                   {:erl_stdlib_errors, :format_error, [:badarg, stacktrace]}
    end

    test "raises FunctionClauseError when a re clause needs args but the frame carries an arity" do
      stacktrace = [{:re, :run, 2, @error_info}]

      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":erl_stdlib_errors.format_re_error/3", [
                     :run,
                     2,
                     :none
                   ]),
                   {:erl_stdlib_errors, :format_error, [:badarg, stacktrace]}
    end

    test "raises FunctionClauseError when a unicode clause needs args but the frame carries an arity" do
      stacktrace = [{:unicode, :characters_to_nfc_binary, 1, @error_info}]

      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":erl_stdlib_errors.format_unicode_error/2", [
                     :characters_to_nfc_binary,
                     1
                   ]),
                   {:erl_stdlib_errors, :format_error, [:badarg, stacktrace]}
    end

    test "raises FunctionClauseError when characters_to_list delegates a frame that carries an arity" do
      stacktrace = [{:unicode, :characters_to_list, 1, @error_info}]

      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":erl_stdlib_errors.format_unicode_error/2", [
                     :characters_to_binary,
                     1
                   ]),
                   {:erl_stdlib_errors, :format_error, [:badarg, stacktrace]}
    end

    test "error frame carries args" do
      stacktrace = wrap_term([])

      top_frame =
        try do
          :erl_stdlib_errors.format_error(:badarg, stacktrace)
        rescue
          _error -> hd(wrap_term(__STACKTRACE__))
        end

      # The server implements this function in Erlang code inside erl_stdlib_errors.erl,
      # so its frame location also carries the corresponding file and line,
      # which the client doesn't mirror.
      assert {module, function, args, location} = top_frame

      assert {module, function, args} == {:erl_stdlib_errors, :format_error, [:badarg, []]}
      assert location[:error_info] == nil
    end
  end
end
