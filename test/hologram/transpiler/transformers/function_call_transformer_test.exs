defmodule Hologram.Transpiler.FunctionCallTransformerTest do
  use ExUnit.Case, async: true

  alias Hologram.Transpiler.AST.{Alias, FunctionCall, Import, IntegerType}
  alias Hologram.Transpiler.FunctionCallTransformer

  @aliases [
    %Alias{module: [:Calendar, :ISO], as: [:Abc]},
    %Alias{module: [:Config, :Reader], as: [:Bcd]}
  ]

  @imports [
    %Import{module: [:Task, :Supervisor]},
    %Import{module: [:Kernel, :ParallelCompiler]}
  ]

  test "current module function" do
    called_module = []
    current_module = [:Abc, :Bcd]
    function = :test
    params = [1, 2]

    result =
      FunctionCallTransformer.transform(
        called_module,
        function,
        params,
        current_module,
        @imports,
        @aliases
      )

    expected_params = [%IntegerType{value: 1}, %IntegerType{value: 2}]

    assert result == %FunctionCall{module: current_module, function: function, params: expected_params}
  end

  test "imported module function" do
    called_module = []
    current_module = [:Abc, :Bcd]
    function = :start_child
    params = [1, 2]

    result =
      FunctionCallTransformer.transform(
        called_module,
        function,
        params,
        current_module,
        @imports,
        @aliases
      )

    expected_params = [%IntegerType{value: 1}, %IntegerType{value: 2}]

    assert result == %FunctionCall{
             module: [:Task, :Supervisor],
             function: function,
             params: expected_params
           }
  end

  test "aliased module function" do
    called_module = []
    current_module = [:Abc, :Bcd]
    function = :start_child
    params = [1, 2]

    result =
      FunctionCallTransformer.transform(
        called_module,
        function,
        params,
        current_module,
        @imports,
        @aliases
      )

    expected_params = [%IntegerType{value: 1}, %IntegerType{value: 2}]

    assert result == %FunctionCall{
             module: [:Task, :Supervisor],
             function: function,
             params: expected_params
           }
  end

  test "fully qualified module function" do
    called_module = [:Cde, :Def]
    current_module = [:Abc, :Bcd]
    function = :test
    params = [1, 2]

    result =
      FunctionCallTransformer.transform(
        called_module,
        function,
        params,
        current_module,
        @imports,
        @aliases
      )

    expected_params = [%IntegerType{value: 1}, %IntegerType{value: 2}]

    assert result == %FunctionCall{module: [:Cde, :Def], function: function, params: expected_params}
  end
end
