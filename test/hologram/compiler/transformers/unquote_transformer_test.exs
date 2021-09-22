defmodule Hologram.Compiler.UnquoteTransformerTest do
  use Hologram.Test.UnitCase , async: true

  alias Hologram.Compiler.{Context, UnquoteTransformer}
  alias Hologram.Compiler.IR.{Unquote, Variable}

  test "transform/2" do
    code = "unquote(abc)"
    ast = ast(code)

    result = UnquoteTransformer.transform(ast, %Context{})
    expected = %Unquote{expression: %Variable{name: :abc}}

    assert result == expected
  end
end
