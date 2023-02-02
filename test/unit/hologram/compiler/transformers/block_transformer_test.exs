defmodule Hologram.Compiler.BlockTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.BlockTransformer
  alias Hologram.Compiler.IR.{Block, IntegerType}

  test "transform/2" do
    ast = {:__block__, [], [1, 2]}
    result = BlockTransformer.transform(ast)

    expected = %Block{
      expressions: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]
    }

    assert result == expected
  end
end
