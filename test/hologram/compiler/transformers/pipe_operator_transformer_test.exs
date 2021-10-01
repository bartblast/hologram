defmodule Hologram.Compiler.PipeOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, PipeOperatorTransformer}
  alias Hologram.Compiler.IR.{FunctionCall, IntegerType}

  test "non-nested pipeline" do
    code = "100 |> div(2)"
    ast = ast(code)

    result = PipeOperatorTransformer.transform(ast, %Context{})

    expected = %FunctionCall{
      function: :div,
      module: Kernel,
      params: [
        %IntegerType{value: 100},
        %IntegerType{value: 2}
      ]
    }

    assert result == expected
  end

  test "nested pipeline" do
    code = "100 |> div(2) |> div(3)"
    ast = ast(code)

    result = PipeOperatorTransformer.transform(ast, %Context{})

    expected = %FunctionCall{
      function: :div,
      module: Kernel,
      params: [
        %FunctionCall{
          function: :div,
          module: Kernel,
          params: [
            %IntegerType{value: 100},
            %IntegerType{value: 2}
          ]
        },
        %IntegerType{value: 3}
      ]
    }

    assert result == expected
  end
end
