defmodule Hologram.Compiler.FunctionCallTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{FunctionCall, IntegerType}
  alias Hologram.Compiler.{Context, FunctionCallTransformer}

  test "transform/4" do
    module_segs = [:Hologram, :Compiler, :FunctionCallTransformerTest]
    function = :test
    params = [1, 2]
    context = %Context{module: [], uses: [], imports: [], aliases: [], attributes: []}

    expected = %FunctionCall{
      module: Hologram.Compiler.FunctionCallTransformerTest,
      function: function,
      params: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]
    }

    result = FunctionCallTransformer.transform(module_segs, function, params, context)
    assert result == expected
  end
end
