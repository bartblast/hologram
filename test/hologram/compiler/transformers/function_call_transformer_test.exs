defmodule Hologram.Compiler.FunctionCallTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{FunctionCall, IntegerType}
  alias Hologram.Compiler.FunctionCallTransformer

  test "transform/4" do
    called_module = [:Abc, :Bcd]
    function = :test
    params = [1, 2]
    context =  [module: [:Xyz], imports: [], aliases: []]

    expected = %FunctionCall{
      module: called_module,
      function: function,
      params: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]
    }

    result = FunctionCallTransformer.transform(called_module, function, params, context)
    assert result == expected
  end
end
