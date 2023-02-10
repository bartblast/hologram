defmodule Hologram.Compiler.PipeOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{FunctionCall, IntegerType}
  alias Hologram.Compiler.PipeOperatorTransformer

  test "non-nested pipeline" do
    code = "100 |> div(2)"
    ast = ast(code)

    result = PipeOperatorTransformer.transform(ast)

    expected = %FunctionCall{
      function: :div,
      module: Kernel,
      args: [
        %IntegerType{value: 100},
        %IntegerType{value: 2}
      ]
    }

    assert result == expected
  end

  test "nested pipeline" do
    code = "100 |> div(2) |> div(3)"
    ast = ast(code)

    result = PipeOperatorTransformer.transform(ast)

    expected = %FunctionCall{
      function: :div,
      module: Kernel,
      args: [
        %FunctionCall{
          function: :div,
          module: Kernel,
          args: [
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
