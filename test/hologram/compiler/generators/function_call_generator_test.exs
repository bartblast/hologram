defmodule Hologram.Compiler.FunctionCallGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{IntegerType, Variable}
  alias Hologram.Compiler.FunctionCallGenerator

  setup do
    [
      context: [],
      function: :abc,
      module: [:Test],
    ]
  end

  test "single param", %{context: context, function: function, module: module} do
    params = [%IntegerType{value: 1}]

    result = FunctionCallGenerator.generate(module, function, params, context)
    expected = "Test.abc({ type: 'integer', value: 1 })"

    assert result == expected
  end

  test "multiple params", %{context: context, function: function, module: module} do
    params = [%IntegerType{value: 1}, %IntegerType{value: 2}]

    result = FunctionCallGenerator.generate(module, function, params, context)

    expected =
      "Test.abc({ type: 'integer', value: 1 }, { type: 'integer', value: 2 })"

    assert result == expected
  end

  test "variable param", %{context: context, function: function, module: module} do
    params = [%Variable{name: :x}]

    result = FunctionCallGenerator.generate(module, function, params, context)
    expected = "Test.abc(x)"

    assert result == expected
  end

  test "non-variable param", %{context: context, function: function, module: module} do
    params = [%IntegerType{value: 1}]

    result = FunctionCallGenerator.generate(module, function, params, context)
    expected = "Test.abc({ type: 'integer', value: 1 })"

    assert result == expected
  end
end
