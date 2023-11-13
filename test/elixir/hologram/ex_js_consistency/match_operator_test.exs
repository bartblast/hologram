defmodule Hologram.ExJsConsistency.MatchOperatorTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/interpreter_test.mjs (matchOperator() section)
  Always update both together.
  """
  use Hologram.Test.BasicCase, async: true

  # The build_match_operator/2 and build_value/1 helpers
  # prevent warnings about incompatible types.

  defp build_match_operator(left, right) do
    ^left = right
  end

  describe "atom type" do
    # :abc = :abc
    test "left atom == right atom" do
      result = :abc = :abc
      assert result == :abc
    end

    # :abc = :xyz
    test "left atom != right atom" do
      assert_raise MatchError, "no match of right hand side value: :xyz", fn ->
        build_match_operator(:abc, :xyz)
      end
    end

    # :abc = 2
    test "left atom != right non-atom" do
      assert_raise MatchError, "no match of right hand side value: 2", fn ->
        build_match_operator(:abc, 2)
      end
    end
  end

  describe "bitstring modifier, signed" do
    test "no type modifier" do
      # 170 == 0b10101010
      result = <<value::signed>> = <<1::1, 0::1, 1::1, 0::1, 1::1, 0::1, 1::1, 0::1>>

      assert result == <<170>>
      assert value == -86
    end

    # <<value::binary-signed>> won't compile
    # test "binary type modifier"

    # <<value::bitstring-signed>> won't compile
    # test "bitstring type modifier"

    test "float type modifier, 64-bit size modifier" do
      result = <<value::float-size(64)-signed>> = <<123.45::size(64)>>

      assert result == <<123.45::size(64)>>
      assert value == 123.45
    end

    test "float type modifier, 32-bit size modifier" do
      result = <<value::float-size(32)-signed>> = <<123.45::size(32)>>

      assert result == <<123.45::size(32)>>
      assert value == 123.44999694824219
    end

    test "float type modifier, 16-bit size modifier" do
      result = <<value::float-size(16)-signed>> = <<123.45::size(16)>>

      assert result == <<123.45::size(16)>>
      assert value == 123.4375
    end

    test "float type modifier, unsupported size modifier" do
      size = 8

      # 170 == 0b10101010
      assert_raise MatchError, "no match of right hand side value: <<170>>", fn ->
        <<_value::float-size(size)-signed>> = <<1::1, 0::1, 1::1, 0::1, 1::1, 0::1, 1::1, 0::1>>
      end
    end

    test "integer type modifier" do
      # 170 == 0b10101010
      result = <<value::integer-signed>> = <<1::1, 0::1, 1::1, 0::1, 1::1, 0::1, 1::1, 0::1>>

      assert result == <<170>>
      assert value == -86
    end

    # <value::utf8-signed>> won't compile
    # test "utf8 type modifier"

    # <value::utf16-signed>> won't compile
    # test "utf16 type modifier"

    # <value::utf32-signed>> won't compile
    # test "utf32 type modifier"
  end

  describe "bitstring modifier, unsigned" do
    test "no type modifier" do
      # 170 == 0b10101010
      result = <<value::unsigned>> = <<1::1, 0::1, 1::1, 0::1, 1::1, 0::1, 1::1, 0::1>>

      assert result == <<170>>
      assert value == 170
    end

    # <<value::binary-unsigned>> won't compile
    # test "binary type modifier"

    # <<value::bitstring-unsigned>> won't compile
    # test "bitstring type modifier"

    test "float type modifier, 64-bit size modifier" do
      result = <<value::float-size(64)-unsigned>> = <<123.45::size(64)>>

      assert result == <<123.45::size(64)>>
      assert value == 123.45
    end

    test "float type modifier, 32-bit size modifier" do
      result = <<value::float-size(32)-unsigned>> = <<123.45::size(32)>>

      assert result == <<123.45::size(32)>>
      assert value == 123.44999694824219
    end

    test "float type modifier, 16-bit size modifier" do
      result = <<value::float-size(16)-unsigned>> = <<123.45::size(16)>>

      assert result == <<123.45::size(16)>>
      assert value == 123.4375
    end

    test "float type modifier, unsupported size modifier" do
      size = 8

      # 170 == 0b10101010
      assert_raise MatchError, "no match of right hand side value: <<170>>", fn ->
        <<_value::float-size(size)-unsigned>> = <<1::1, 0::1, 1::1, 0::1, 1::1, 0::1, 1::1, 0::1>>
      end
    end

    test "integer type modifier" do
      # 170 == 0b10101010
      result = <<value::integer-unsigned>> = <<1::1, 0::1, 1::1, 0::1, 1::1, 0::1, 1::1, 0::1>>

      assert result == <<170>>
      assert value == 170
    end

    # <value::utf8-unsigned>> won't compile
    # test "utf8 type modifier"

    # <value::utf16-unsigned>> won't compile
    # test "utf16 type modifier"

    # <value::utf32-unsigned>> won't compile
    # test "utf32 type modifier"
  end

  describe "bistring type" do
    # <<>> = <<>>
    test "left empty bitstring == right empty bitstring" do
      result = <<>> = <<>>
      assert result == <<>>
    end

    # <<>> = <<1::1, 0::1>>
    test "left empty bitstring != right non-empty bitstring" do
      assert_raise MatchError, "no match of right hand side value: <<2::size(2)>>", fn ->
        <<>> = <<1::1, 0::1>>
      end
    end

    # <<>> = :abc
    test "left empty bitstring != right non-bitstring" do
      assert_raise MatchError, "no match of right hand side value: :abc", fn ->
        <<>> = build_value(:abc)
      end
    end

    test "left literal single-segment bitstring == right literal single-segment bitstring" do
      result = <<1::integer>> = <<1::integer>>
      assert result == <<1::integer>>
    end

    test "left literal single-segment bitstring != right literal single-segment bitstring" do
      assert_raise MatchError, "no match of right hand side value: <<2>>", fn ->
        <<1::integer>> = <<2::integer>>
      end
    end

    test "left literal single-segment bitstring != right non-bitstring" do
      assert_raise MatchError, "no match of right hand side value: :abc", fn ->
        <<1::integer>> = build_value(:abc)
      end
    end

    test "multiple literal bitstring segments" do
      result = <<1::1, 0::1>> = <<1::1, 0::1>>

      assert result == <<1::1, 0::1>>
    end

    test "multiple literal float segments" do
      result = <<1.0::float, 2.0::float>> = <<1.0::float, 2.0::float>>

      assert result == <<1.0::float, 2.0::float>>
    end

    test "multiple literal integer segments" do
      result = <<1::integer, 2::integer>> = <<1::integer, 2::integer>>

      assert result == <<1::integer, 2::integer>>
    end

    test "multiple literal string segments" do
      result = <<"aaa"::utf8, "bbb"::utf8>> = <<"aaa"::utf8, "bbb"::utf8>>

      assert result == <<"aaa"::utf8, "bbb"::utf8>>
    end

    # <<x::integer>> = <<1>>
    test "left single-segment bitstring with variable pattern == right bistring" do
      result = <<x::integer>> = <<1>>

      assert result == <<1>>
      assert x == 1
    end

    # <<x::integer, y::integer>> = <<1, 2>>
    test "left multiple-segment bitstring with variable patterns == right bitstring" do
      result = <<x::integer, y::integer>> = <<1, 2>>

      assert result == <<1, 2>>
      assert x == 1
      assert y == 2
    end

    # <<3, y::integer>> = <<1, 2>>
    test "first segment in left multi-segment bitstring doesn't match" do
      assert_raise MatchError, "no match of right hand side value: <<1, 2>>", fn ->
        <<3, _y::integer>> = <<1, 2>>
      end
    end

    # <<1, 2::size(7)>> = <<1, 2>>
    test "last segment in left multi-segment bitstring doesn't match, because there are too few bits" do
      assert_raise MatchError, "no match of right hand side value: <<1, 2>>", fn ->
        <<1, 2::size(7)>> = <<1, 2>>
      end
    end

    # <<1, 2::size(9)>> = <<1, 2>>
    test "last segment in left multi-segment bitstring doesn't match, because there are too many bits" do
      assert_raise MatchError, "no match of right hand side value: <<1, 2>>", fn ->
        <<1, 2::size(9)>> = <<1, 2>>
      end
    end
  end

  # TODO: finish overhaul, remember about JavaScript interpreter tests
  # describe "cons pattern" do
  #   test "left cons pattern == right list, cons pattern head and tail are variables" do
  #     result = [h | t] = [1, 2, 3]

  #     assert result == [1, 2, 3]
  #     assert h == 1
  #     assert t == [2, 3]
  #   end

  #   test "left cons pattern == right list, cons pattern head is variable, tail is literal" do
  #     result = [h | [2, 3]] = [1, 2, 3]

  #     assert result == [1, 2, 3]
  #     assert h == 1
  #   end

  #   test "left cons pattern == right list, cons pattern head is literal, tail is variable" do
  #     result = [1 | t] = [1, 2, 3]

  #     assert result == [1, 2, 3]
  #     assert t == [2, 3]
  #   end

  #   test "left cons pattern == right list, cons pattern head and tail are literals" do
  #     result = [1 | [2, 3]] = [1, 2, 3]

  #     assert result == [1, 2, 3]
  #   end

  #   test "raises match error if right is not a list" do
  #     assert_raise MatchError, "no match of right hand side value: 123", fn ->
  #       [_h | _t] = build_value(123)
  #     end
  #   end

  #   test "raises match error if right is an empty list" do
  #     assert_raise MatchError, "no match of right hand side value: []", fn ->
  #       [_h | _t] = build_value([])
  #     end
  #   end

  #   test "raises match error if head doesn't match" do
  #     assert_raise MatchError, "no match of right hand side value: [1, 2, 3]", fn ->
  #       [4 | [2, 3]] = build_value([1, 2, 3])
  #     end
  #   end

  #   test "raises match error if tail doesn't match" do
  #     assert_raise MatchError, "no match of right hand side value: [1, 2, 3]", fn ->
  #       [1 | [4, 3]] = build_value([1, 2, 3])
  #     end
  #   end
  # end

  # TODO: finish overhaul, remember about JavaScript interpreter tests
  # describe "float type" do
  #   test "left float == right float" do
  #     result = 2.0 = 2.0
  #     assert result == 2.0
  #   end

  #   test "left float != right float" do
  #     assert_raise MatchError, "no match of right hand side value: 3.0", fn ->
  #       2.0 = build_value(3.0)
  #     end
  #   end

  #   test "left float != right non-float" do
  #     assert_raise MatchError, "no match of right hand side value: :abc", fn ->
  #       2.0 = build_value(:abc)
  #     end
  #   end
  # end

  # TODO: finish overhaul, remember about JavaScript interpreter tests
  # describe "integer type" do
  #   test "left integer == right integer" do
  #     result = 2 = 2
  #     assert result == 2
  #   end

  #   test "left integer != right integer" do
  #     assert_raise MatchError, "no match of right hand side value: 3", fn ->
  #       2 = build_value(3)
  #     end
  #   end

  #   test "left integer != right non-integer" do
  #     assert_raise MatchError, "no match of right hand side value: :abc", fn ->
  #       2 = build_value(:abc)
  #     end
  #   end
  # end

  # TODO: finish overhaul, remember about JavaScript interpreter tests
  # describe "list type" do
  #   test "left list == right list" do
  #     result = [1, 2] = [1, 2]
  #     assert result == [1, 2]
  #   end

  #   test "left list != right list" do
  #     assert_raise MatchError, "no match of right hand side value: [1, 3]", fn ->
  #       [1, 2] = build_value([1, 3])
  #     end
  #   end

  #   test "left list != right non-list" do
  #     assert_raise MatchError, "no match of right hand side value: :abc", fn ->
  #       [1, 2] = build_value(:abc)
  #     end
  #   end

  #   test "left list has variables" do
  #     result = [x, 2, y] = [1, 2, 3]

  #     assert result == [1, 2, 3]
  #     assert x == 1
  #     assert y == 3
  #   end
  # end

  # Order of keys in maps is undefined (consider this in regard to error messages).
  describe "map type" do
    # %{x: 1, y: 2} = %{x: 1, y: 2}
    test "left and right maps have the same items" do
      result = %{x: 1, y: 2} = %{x: 1, y: 2}
      assert result == %{x: 1, y: 2}
    end

    # %{x: 1, y: 2} = %{x: 1, y: 2, z: 3}
    test "right map has all the same items as the left map plus additional ones" do
      result = %{x: 1, y: 2} = %{x: 1, y: 2, z: 3}
      assert result == %{x: 1, y: 2, z: 3}
    end

    #  %{x: 1, y: 2, z: 3} = %{x: 1, y: 2}
    test "right map is missing some some keys from the left map" do
      assert_raise MatchError, "no match of right hand side value: %{y: 2, x: 1}", fn ->
        %{x: 1, y: 2, z: 3} = build_value(%{x: 1, y: 2})
      end
    end

    # %{x: 1, y: 2} = %{x: 1, y: 3}
    test "some values in the left map don't match values in the right map" do
      assert_raise MatchError, "no match of right hand side value: %{y: 3, x: 1}", fn ->
        %{x: 1, y: 2} = %{x: 1, y: 3}
      end
    end

    # %{x: 1, y: 2} = :abc
    test "left map != right non-map" do
      assert_raise MatchError, "no match of right hand side value: :abc", fn ->
        %{x: 1, y: 2} = build_value(:abc)
      end
    end

    # %{k: x, m: 2, n: z} = %{k: 1, m: 2, n: 3}
    test "left map has variables" do
      result = %{k: x, m: 2, n: z} = %{k: 1, m: 2, n: 3}

      assert result == %{k: 1, m: 2, n: 3}
      assert x == 1
      assert z == 3
    end

    # %{x: 1, y: 2} = %{}
    test "left is a non-empty map, right is an empty map" do
      assert_raise MatchError, "no match of right hand side value: %{}", fn ->
        %{x: 1, y: 2} = build_value(%{})
      end
    end

    # %{} = %{x: 1, y: 2}
    test "left is an empty map, right is a non-empty map" do
      result = %{} = %{x: 1, y: 2}
      assert result == %{x: 1, y: 2}
    end

    # %{} = %{}
    test "both left and right maps are empty" do
      result = %{} = %{}
      assert result == %{}
    end
  end

  # _var = 2
  test "match placeholder" do
    result = _var = 2
    assert result == 2
  end

  describe "nested match operators" do
    test "x = 2 = 2" do
      result = x = 2 = 2

      assert result == 2
      assert x == 2
    end

    test "x = 2 = 3" do
      assert_raise MatchError, "no match of right hand side value: 3", fn ->
        _x = 2 = build_value(3)
      end
    end

    test "2 = x = 2" do
      result = 2 = x = 2

      assert result == 2
      assert x == 2
    end

    test "2 = x = 3" do
      assert_raise MatchError, "no match of right hand side value: 3", fn ->
        2 = _x = build_value(3)
      end
    end

    test "2 = 2 = x, (x = 2)" do
      x = 2
      result = 2 = 2 = x

      assert result == 2
      assert x == 2
    end

    test "2 = 2 = x, (x = 3)" do
      assert_raise MatchError, "no match of right hand side value: 3", fn ->
        x = 3
        2 = 2 = build_value(x)
      end
    end

    test "1 = 2 = x, (x = 2)" do
      assert_raise MatchError, "no match of right hand side value: 2", fn ->
        x = 2
        1 = 2 = build_value(x)
      end
    end

    test "y = x + (x = 3) + x, (x = 11)" do
      x = 11
      result = y = x + (x = 3) + x

      assert result == 25
      assert x == 3
      assert y == 25
    end

    test "[1 = 1] = [1 = 1]" do
      result = [1 = 1] = [1 = 1]
      assert result == [1]
    end

    test "[1 = 1] = [1 = 2]" do
      assert_raise MatchError, "no match of right hand side value: 2", fn ->
        [1 = 1] = [1 = build_value(2)]
      end
    end

    test "[1 = 1] = [2 = 1]" do
      assert_raise MatchError, "no match of right hand side value: 1", fn ->
        [1 = 1] = [2 = build_value(1)]
      end
    end

    # TODO: JavaScript error message for this case is inconsistent with Elixir error message (see test/javascript/interpreter_test.mjs)
    test "[1 = 2] = [1 = 1]" do
      assert_raise MatchError, "no match of right hand side value: [1]", fn ->
        x = build_value(2)
        [1 = ^x] = [1 = 1]
      end
    end

    # TODO: JavaScript error message for this case is inconsistent with Elixir error message (see test/javascript/interpreter_test.mjs)
    test "[2 = 1] = [1 = 1]" do
      assert_raise MatchError, "no match of right hand side value: [1]", fn ->
        x = build_value(2)
        [^x = 1] = [1 = 1]
      end
    end

    test "{a = b, 2, 3} = {1, c = d, 3} = {1, 2, e = f}" do
      f = 3
      result = {a = b, 2, 3} = {1, c = d, 3} = {1, 2, e = f}

      assert result == {1, 2, 3}
      assert a == 1
      assert b == 1
      assert c == 2
      assert d == 2
      assert e == 3
      assert f == 3
    end
  end

  describe "nested match pattern (with uresolved variables)" do
    test "[[a | b] = [c | d]] = [[1, 2, 3]]" do
      result = [[a | b] = [c | d]] = [[1, 2, 3]]

      assert result == [[1, 2, 3]]
      assert a == 1
      assert b == [2, 3]
      assert c == 1
      assert d == [2, 3]
    end

    test "[[[a | b] = [c | d]] = [[e | f]]] = [[[1, 2, 3]]]" do
      result = [[[a | b] = [c | d]] = [[e | f]]] = [[[1, 2, 3]]]

      assert result == [[[1, 2, 3]]]
      assert a == 1
      assert b == [2, 3]
      assert c == 1
      assert d == [2, 3]
      assert e == 1
      assert f == [2, 3]
    end

    test "[[a, b] = [c, d]] = [[1, 2]]" do
      result = [[a, b] = [c, d]] = [[1, 2]]

      assert result == [[1, 2]]
      assert a == 1
      assert b == 2
      assert c == 1
      assert d == 2
    end

    test "[[[a, b] = [c, d]] = [[e, f]]] = [[[1, 2]]]" do
      result = [[[a, b] = [c, d]] = [[e, f]]] = [[[1, 2]]]

      assert result == [[[1, 2]]]
      assert a == 1
      assert b == 2
      assert c == 1
      assert d == 2
      assert e == 1
      assert f == 2
    end

    test "[x = y] = [1]" do
      result = [x = y] = [1]

      assert result == [1]
      assert x == 1
      assert y == 1
    end

    test "[1 = x] = [1]" do
      result = [1 = x] = [1]

      assert result == [1]
      assert x == 1
    end

    test "[x = 1] = [1]" do
      result = [x = 1] = [1]

      assert result == [1]
      assert x == 1
    end

    test "[x = y = z] = [1]" do
      result = [x = y = z] = [1]

      assert result == [1]
      assert x == 1
      assert y == 1
      assert z == 1
    end

    test "[1 = x = y] = [1]" do
      result = [1 = x = y] = [1]

      assert result == [1]
      assert x == 1
      assert y == 1
    end

    test "[x = 1 = y] = [1]" do
      result = [x = 1 = y] = [1]

      assert result == [1]
      assert x == 1
      assert y == 1
    end

    test "[x = y = 1] = [1]" do
      result = [x = y = 1] = [1]

      assert result == [1]
      assert x == 1
      assert y == 1
    end

    test "[v = x = y = z] = [1]" do
      result = [v = x = y = z] = [1]

      assert result == [1]
      assert v == 1
      assert x == 1
      assert y == 1
      assert z == 1
    end

    test "[1 = x = y = z] = [1]" do
      result = [1 = x = y = z] = [1]

      assert result == [1]
      assert x == 1
      assert y == 1
      assert z == 1
    end

    test "[x = 1 = y = z] = [1]" do
      result = [x = 1 = y = z] = [1]

      assert result == [1]
      assert x == 1
      assert y == 1
      assert z == 1
    end

    test "[x = y = 1 = z] = [1]" do
      result = [x = y = 1 = z] = [1]

      assert result == [1]
      assert x == 1
      assert y == 1
      assert z == 1
    end

    test "[x = y = z = 1] = [1]" do
      result = [x = y = z = 1] = [1]

      assert result == [1]
      assert x == 1
      assert y == 1
      assert z == 1
    end

    test "[x = y = z] = [a = b = c = 2]" do
      result = [x = y = z] = [a = b = c = 2]

      assert result == [2]
      assert a == 2
      assert b == 2
      assert c == 2
      assert x == 2
      assert y == 2
      assert z == 2
    end

    test "%{x: %{a: a, b: b} = %{a: c, b: d}} = %{x: %{a: 1, b: 2}}" do
      result = %{x: %{a: a, b: b} = %{a: c, b: d}} = %{x: %{a: 1, b: 2}}

      assert result == %{x: %{a: 1, b: 2}}
      assert a == 1
      assert b == 2
      assert c == 1
      assert d == 2
    end

    test "%{y: %{x: %{a: a, b: b} = %{a: c, b: d}} = %{x: %{a: e, b: f}}} = %{y: %{x: %{a: 1, b: 2}}}" do
      result =
        %{y: %{x: %{a: a, b: b} = %{a: c, b: d}} = %{x: %{a: e, b: f}}} = %{
          y: %{x: %{a: 1, b: 2}}
        }

      assert result == %{y: %{x: %{a: 1, b: 2}}}
      assert a == 1
      assert b == 2
      assert c == 1
      assert d == 2
      assert e == 1
      assert f == 2
    end

    test "{{a, b} = {c, d}} = {{1, 2}}" do
      result = {{a, b} = {c, d}} = {{1, 2}}

      assert result == {{1, 2}}
      assert a == 1
      assert b == 2
      assert c == 1
      assert d == 2
    end

    test "{{{a, b} = {c, d}} = {{e, f}}} = {{{1, 2}}}" do
      result = {{{a, b} = {c, d}} = {{e, f}}} = {{{1, 2}}}

      assert result == {{{1, 2}}}
      assert a == 1
      assert b == 2
      assert c == 1
      assert d == 2
      assert e == 1
      assert f == 2
    end
  end

  # TODO: finish overhaul, remember about JavaScript interpreter tests
  # describe "tuple type" do
  #   test "left tuple == right tuple" do
  #     result = {1, 2} = {1, 2}
  #     assert result == {1, 2}
  #   end

  #   test "left tuple != right tuple" do
  #     assert_raise MatchError, "no match of right hand side value: {1, 3}", fn ->
  #       {1, 2} = build_value({1, 3})
  #     end
  #   end

  #   test "left tuple != right non-tuple" do
  #     assert_raise MatchError, "no match of right hand side value: :abc", fn ->
  #       {1, 2} = build_value(:abc)
  #     end
  #   end

  #   test "left tuple has variables" do
  #     result = {x, 2, y} = {1, 2, 3}

  #     assert result == {1, 2, 3}
  #     assert x == 1
  #     assert y == 3
  #   end
  # end

  describe "variable pattern" do
    # x = 2
    test "variable pattern == anything" do
      result = x = 2

      assert result == 2
      assert x == 2
    end

    # [x, x] = [1, 1]
    test "multiple variables with the same name being matched to the same value" do
      result = [x, x] = [1, 1]

      assert result == [1, 1]
      assert x == 1
    end

    # [x, x] = [1, 2]
    test "multiple variables with the same name being matched to the different values" do
      assert_raise MatchError, "no match of right hand side value: [1, 2]", fn ->
        [x, x] = build_value([1, 2])
      end
    end
  end
end
