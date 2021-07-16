defmodule Hologram.Compiler.AliasTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.AliasTransformer
  alias Hologram.Compiler.IR.Alias

  test "default 'as' option" do
    code = "alias Abc.Bcd"
    {:alias, _, ast} = ast(code)

    result = AliasTransformer.transform(ast)
    expected = %Alias{module: [:Abc, :Bcd], as: [:Bcd]}

    assert result == expected
  end

  test "one-part 'as' option" do
    code = "alias Abc.Bcd, as: Xyz"
    {:alias, _, ast} = ast(code)

    result = AliasTransformer.transform(ast)
    expected = %Alias{module: [:Abc, :Bcd], as: [:Xyz]}

    assert result == expected
  end

  test "multiple-part 'as' option" do
    code = "alias Abc.Bcd, as: Xyz.Kmn"
    {:alias, _, ast} = ast(code)

    result = AliasTransformer.transform(ast)
    expected = %Alias{module: [:Abc, :Bcd], as: [:Xyz, :Kmn]}

    assert result == expected
  end

  test "'warn' option" do
    code = "alias Abc.Bcd, warn: false"
    {:alias, _, ast} = ast(code)

    result = AliasTransformer.transform(ast)
    expected = %Alias{module: [:Abc, :Bcd], as: [:Bcd]}

    assert result == expected
  end

  test "'as' option + 'warn' option" do
    code = "alias Abc.Bcd, as: Xyz, warn: false"
    {:alias, _, ast} = ast(code)

    result = AliasTransformer.transform(ast)
    expected = %Alias{module: [:Abc, :Bcd], as: [:Xyz]}

    assert result == expected
  end
end
