defmodule Hologram.Compiler.AliasTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.AliasTransformer
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR.Alias

  test "aliases tuple" do
    code = "Abc.Bcd"
    ast = ast(code)

    result = AliasTransformer.transform(ast, %Context{})
    expected = %Alias{segments: [:Abc, :Bcd]}

    assert result == expected
  end

  test "atom" do
    result = AliasTransformer.transform(Abc.Bcd, %Context{})
    expected = %Alias{segments: [:Abc, :Bcd]}

    assert result == expected
  end
end
