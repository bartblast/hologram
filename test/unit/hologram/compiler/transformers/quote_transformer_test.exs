defmodule Hologram.Compiler.QuoteTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, QuoteTransformer}
  alias Hologram.Compiler.IR.{Block, IntegerType, Quote}

  test "transform/2" do
    code = """
    quote do
      1
      2
    end
    """

    ast = ast(code)

    result = QuoteTransformer.transform(ast, %Context{})

    expected = %Quote{
      body: %Block{expressions: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]}
    }

    assert result == expected
  end
end
