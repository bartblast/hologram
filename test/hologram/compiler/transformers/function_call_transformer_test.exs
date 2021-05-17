defmodule Hologram.Compiler.FunctionCallTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.AST.{Alias, FunctionCall, Import, IntegerType}
  alias Hologram.Compiler.FunctionCallTransformer

  setup do
    [
      module: [:Abc, :Bcd],
      imports: [
        %Import{module: [:Task, :Supervisor]},
        %Import{module: [:Kernel, :ParallelCompiler]}
      ],
      aliases: [
        %Alias{module: [:Calendar, :ISO], as: [:Abc]},
        %Alias{module: [:Config, :Reader], as: [:Bcd]}
      ]
    ]
  end

  test "current module function", context do
    called_module = []
    function = :test
    params = [1, 2]

    result = FunctionCallTransformer.transform(called_module, function, params, context)

    expected_params = [%IntegerType{value: 1}, %IntegerType{value: 2}]

    assert result == %FunctionCall{module: context[:module], function: function, params: expected_params}
  end

  test "imported module function", context do
    called_module = []
    function = :start_child
    params = [1, 2]

    result = FunctionCallTransformer.transform(called_module, function, params, context)

    expected_params = [%IntegerType{value: 1}, %IntegerType{value: 2}]

    assert result == %FunctionCall{
             module: [:Task, :Supervisor],
             function: function,
             params: expected_params
           }
  end

  test "aliased module function", context do
    called_module = []
    function = :start_child
    params = [1, 2]

    result = FunctionCallTransformer.transform(called_module, function, params, context)

    expected_params = [%IntegerType{value: 1}, %IntegerType{value: 2}]

    assert result == %FunctionCall{
             module: [:Task, :Supervisor],
             function: function,
             params: expected_params
           }
  end

  test "fully qualified module function", context do
    called_module = [:Cde, :Def]
    function = :test
    params = [1, 2]

    result = FunctionCallTransformer.transform(called_module, function, params, context)

    expected_params = [%IntegerType{value: 1}, %IntegerType{value: 2}]

    assert result == %FunctionCall{module: [:Cde, :Def], function: function, params: expected_params}
  end
end
