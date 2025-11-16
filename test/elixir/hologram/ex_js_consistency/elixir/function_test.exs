defmodule Hologram.ExJsConsistency.Elixir.FunctionTest.Sample do
  def double(value) when is_integer(value), do: value * 2
end

defmodule Hologram.ExJsConsistency.Elixir.FunctionTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/elixir/function_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  alias Hologram.ExJsConsistency.Elixir.FunctionTest.Sample

  @moduletag :consistency

  describe "capture/3" do
    test "returns a function capture" do
      fun = Function.capture(Sample, :double, 1)

      assert fun.(4) == 8
    end

    test "raises ArgumentError when module is not an atom" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not an atom"),
                   {Function, :capture, ["Sample", :double, 1]}
    end

    test "raises ArgumentError when function name is not an atom" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not an atom"),
                   {Function, :capture, [Sample, "double", 1]}
    end

    test "raises ArgumentError when arity is not an integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "not an integer"),
                   {Function, :capture, [Sample, :double, 1.0]}
    end

    test "raises ArgumentError when arity is negative" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "out of range"),
                   {Function, :capture, [Sample, :double, -1]}
    end

    test "raises ArgumentError when arity is too large" do
      assert_error ArgumentError,
                   "argument error",
                   {Function, :capture, [Sample, :double, 256]}
    end
  end

  describe "info/1" do
    test "returns function metadata" do
      fun = &Sample.double/1
      info = Function.info(fun)

      assert Keyword.get(info, :module) == Sample
      assert Keyword.get(info, :name) == :double
      assert Keyword.get(info, :arity) == 1
      assert Keyword.get(info, :env) == []
      assert Keyword.get(info, :type) == :external
    end

    test "raises ArgumentError when first argument is not a function" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a fun"),
                   fn -> Function.info(:foo) end
    end
  end

  describe "info/2" do
    test "returns requested info tuple" do
      fun = &Sample.double/1
      assert Function.info(fun, :arity) == {:arity, 1}
    end

    test "raises ArgumentError when item is invalid" do
      fun = &Sample.double/1

      assert_error ArgumentError,
                   build_argument_error_msg(2, "invalid item"),
                   fn -> Function.info(fun, :invalid) end
    end
  end

  describe "identity/1" do
    test "returns the input value" do
      assert Function.identity("hologram") == "hologram"
    end
  end
end
