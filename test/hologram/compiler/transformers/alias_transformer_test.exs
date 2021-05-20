defmodule Hologram.Compiler.AliasTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.AliasTransformer
  alias Hologram.Compiler.IR.Alias

  test "default as" do
    code = "alias Abc.Bcd"
    {:alias, _, ast} = ast(code)

    result = AliasTransformer.transform(ast)
    expected = %Alias{module: [:Abc, :Bcd], as: [:Bcd]}

    assert result == expected
  end

  test "specified one-part as" do
    code = "alias Abc.Bcd, as: Xyz"
    {:alias, _, ast} = ast(code)

    result = AliasTransformer.transform(ast)
    expected = %Alias{module: [:Abc, :Bcd], as: [:Xyz]}

    assert result == expected
  end

  test "specified multiple-part as" do
    code = "alias Abc.Bcd, as: Xyz.Kmn"
    {:alias, _, ast} = ast(code)

    result = AliasTransformer.transform(ast)
    expected = %Alias{module: [:Abc, :Bcd], as: [:Xyz, :Kmn]}

    assert result == expected
  end
end
