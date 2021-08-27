defmodule Hologram.Compiler.FunctionCallGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, FunctionCallGenerator, Opts}
  alias Hologram.Compiler.IR.{IntegerType, Variable}

  @function :abc
  @module Test

  test "single param" do
    params = [%IntegerType{value: 1}]

    result = FunctionCallGenerator.generate(@module, @function, params, %Context{}, %Opts{})
    expected = "Elixir_Test.abc({ type: 'integer', value: 1 })"

    assert result == expected
  end

  test "multiple params" do
    params = [%IntegerType{value: 1}, %IntegerType{value: 2}]

    result = FunctionCallGenerator.generate(@module, @function, params, %Context{}, %Opts{})
    expected = "Elixir_Test.abc({ type: 'integer', value: 1 }, { type: 'integer', value: 2 })"

    assert result == expected
  end

  test "variable param" do
    params = [%Variable{name: :x}]

    result = FunctionCallGenerator.generate(@module, @function, params, %Context{}, %Opts{})
    expected = "Elixir_Test.abc(x)"

    assert result == expected
  end

  test "non-variable param" do
    params = [%IntegerType{value: 1}]

    result = FunctionCallGenerator.generate(@module, @function, params, %Context{}, %Opts{})
    expected = "Elixir_Test.abc({ type: 'integer', value: 1 })"

    assert result == expected
  end

  test "function name" do
    function = "test?"
    params = []

    result = FunctionCallGenerator.generate(@module, function, params, %Context{}, %Opts{})
    expected = "Elixir_Test.test$question()"

    assert result == expected
  end
end
