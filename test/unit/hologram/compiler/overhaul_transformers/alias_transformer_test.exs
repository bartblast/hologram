defmodule Hologram.Compiler.AliasTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.AliasTransformer
  alias Hologram.Compiler.IR.Alias

  test "aliases tuple" do
    code = "Abc.Bcd"
    ast = ast(code)

    result = AliasTransformer.transform(ast)
    expected = %Alias{segments: [:Abc, :Bcd]}

    assert result == expected
  end

  test "atom" do
    result = AliasTransformer.transform(Abc.Bcd)
    expected = %Alias{segments: [:Abc, :Bcd]}

    assert result == expected
  end
end
