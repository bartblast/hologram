defmodule Hologram.ExJsConsistency.Erlang.MathTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/math_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  # describe("Erlang_Math", () => {
  #   it("exp/1", () => {
  #     const exp = Erlang_Math["exp/1"];

  #     describe("returns correct value", () => {
  #       const number = Type.float(2);

  #       const result = exp(number);
  #       const expected = Type.float(7.38905609893065);

  #       assert.deepStrictEqual(result, expected);
  #     });

  #     describe("returns correct value if passing negative value", () => {
  #       const number = Type.float(-2);

  #       const result = exp(number);
  #       const expected = Type.float(0.1353352832366127);

  #       assert.deepStrictEqual(result, expected);
  #     });

  #     describe("returns correct value if passing one", () => {
  #       const number = Type.float(1.0);

  #       const result = exp(number);
  #       const expected = Type.float(2.718281828459045);

  #       assert.deepStrictEqual(result, expected);
  #     });

  #     describe("returns correct value if passing zero", () => {
  #       const number = Type.float(0);

  #       const result = exp(number);
  #       const expected = Type.float(1.0);

  #       assert.deepStrictEqual(result, expected);
  #     });

  #     describe("raises ArgumentError if the argument is a string", () => {
  #       const integerString = Type.string("12345");

  #       assertBoxedError(() => exp(integerString), "ArgumentError", Interpreter.buildArgumentErrorMsg(1, "not a float or integer"));
  #     });

  #     describe("raises ArgumentError if the argument is a list", () => {
  #       const list = Type.list([Type.integer(1), Type.integer(2)]);

  #       assertBoxedError(() => exp(list), "ArgumentError", Interpreter.buildArgumentErrorMsg(1, "not a float or integer"));
  #     });
  #   });
  # });


  describe "exp/1" do
    test "returns correct value" do
      number = 2.0

      result = :math.exp(number)
      expected = 7.38905609893065

      assert result == expected
    end

    test "returns correct value if passing negative value" do
      number = -2.0

      result = :math.exp(number)
      expected = 0.1353352832366127

      assert result == expected
    end

    test "returns correct value if passing one" do
      number = 1.0

      result = :math.exp(number)
      expected = 2.718281828459045

      assert result == expected
    end

    test "returns correct value if passing zero" do
      number = 0.0

      result = :math.exp(number)
      expected = 1.0

      assert result == expected
    end

    test "raises ArgumentError if the argument is a string" do
      integer_string = "12345"

      assert_error ArgumentError, ~r"errors were found at the given arguments:\n\n  \* 1st argument: not a number", fn ->
        :math.exp(integer_string)
      end
    end

    test "raises ArgumentError if the argument is a list" do
      list = [1, 2]

      assert_error ArgumentError, ~r"errors were found at the given arguments:\n\n  \* 1st argument: not a number", fn ->
        :math.exp(list)
      end
    end
  end
end
