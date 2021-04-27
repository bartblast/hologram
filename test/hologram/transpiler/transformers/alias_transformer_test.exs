defmodule Hologram.Transpiler.AliasTransformerTest do
  use ExUnit.Case, async: true

  alias Hologram.Transpiler.AliasTransformer
  alias Hologram.Transpiler.AST.Alias

  test "default as" do
    # alias Abc.Bcd
    ast = [{:__aliases__, [line: 1], [:Abc, :Bcd]}]

    result = AliasTransformer.transform(ast)
    expected = %Alias{module: [:Abc, :Bcd], as: [:Bcd]}

    assert result == expected
  end

  test "specified one-part as" do
    # alias Abc.Bcd, as: Xyz
    ast =
      [
        {:__aliases__, [line: 1], [:Abc, :Bcd]},
        [as: {:__aliases__, [line: 1], [:Xyz]}]
      ]

    result = AliasTransformer.transform(ast)
    expected = %Alias{module: [:Abc, :Bcd], as: [:Xyz]}

    assert result == expected
  end

  test "specified multiple-part as" do
    # alias Abc.Bcd, as: Xyz.Kmn
    ast =
      [
        {:__aliases__, [line: 1], [:Abc, :Bcd]},
        [as: {:__aliases__, [line: 1], [:Xyz, :Kmn]}]
      ]

    result = AliasTransformer.transform(ast)
    expected = %Alias{module: [:Abc, :Bcd], as: [:Xyz, :Kmn]}

    assert result == expected
  end
end
