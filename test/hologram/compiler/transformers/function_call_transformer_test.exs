defmodule Hologram.Compiler.FunctionCallTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{FunctionCall, IntegerType}
  alias Hologram.Compiler.{Context, FunctionCallTransformer}

  test "params list" do
    module_segs = [:Hologram, :Compiler, :FunctionCallTransformerTest]
    function = :test
    params = [1, 2]

    expected = %FunctionCall{
      module: Hologram.Compiler.FunctionCallTransformerTest,
      function: function,
      params: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]
    }

    result = FunctionCallTransformer.transform(module_segs, function, params, %Context{})
    assert result == expected
  end

  test "params nil" do
    module_segs = [:Hologram, :Compiler, :FunctionCallTransformerTest]
    function = :test
    params = nil

    expected = %FunctionCall{
      module: Hologram.Compiler.FunctionCallTransformerTest,
      function: function,
      params: []
    }

    result = FunctionCallTransformer.transform(module_segs, function, params, %Context{})
    assert result == expected
  end
end
