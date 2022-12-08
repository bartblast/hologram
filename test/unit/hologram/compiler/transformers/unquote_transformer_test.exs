defmodule Hologram.Compiler.UnquoteTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR.Unquote
  alias Hologram.Compiler.IR.Variable
  alias Hologram.Compiler.UnquoteTransformer

  test "transform/2" do
    code = "unquote(abc)"
    ast = ast(code)

    result = UnquoteTransformer.transform(ast, %Context{})
    expected = %Unquote{expression: %Variable{name: :abc}}

    assert result == expected
  end
end
