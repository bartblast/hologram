defmodule Hologram.Compiler.QuoteTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{Block, IntegerType, Quote}
  alias Hologram.Compiler.QuoteTransformer

  test "transform/2" do
    code = """
    quote do
      1
      2
    end
    """

    ast = ast(code)

    result = QuoteTransformer.transform(ast)

    expected = %Quote{
      body: %Block{
        expressions: [
          %IntegerType{value: 1},
          %IntegerType{value: 2}
        ]
      }
    }

    assert result == expected
  end
end
