defmodule Hologram.Compiler.AliasTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.AliasTransformer
  alias Hologram.Compiler.IR.Alias

  @expected_module Hologram.Test.Fixtures.Compiler.AliasTransformer.Module1

  test "default 'as' option" do
    code = "alias Hologram.Test.Fixtures.Compiler.AliasTransformer.Module1"
    {:alias, _, ast} = ast(code)

    result = AliasTransformer.transform(ast)
    expected = %Alias{module: @expected_module, as: [:Module1]}

    assert result == expected
  end

  test "one-part 'as' option" do
    code = "alias Hologram.Test.Fixtures.Compiler.AliasTransformer.Module1, as: Xyz"
    {:alias, _, ast} = ast(code)

    result = AliasTransformer.transform(ast)
    expected = %Alias{module: @expected_module, as: [:Xyz]}

    assert result == expected
  end

  test "multiple-part 'as' option" do
    code = "alias Hologram.Test.Fixtures.Compiler.AliasTransformer.Module1, as: Xyz.Kmn"
    {:alias, _, ast} = ast(code)

    result = AliasTransformer.transform(ast)
    expected = %Alias{module: @expected_module, as: [:Xyz, :Kmn]}

    assert result == expected
  end

  test "'warn' option" do
    code = "alias Hologram.Test.Fixtures.Compiler.AliasTransformer.Module1, warn: false"
    {:alias, _, ast} = ast(code)

    result = AliasTransformer.transform(ast)
    expected = %Alias{module: @expected_module, as: [:Module1]}

    assert result == expected
  end

  test "'as' option + 'warn' option" do
    code = "alias Hologram.Test.Fixtures.Compiler.AliasTransformer.Module1, as: Xyz, warn: false"
    {:alias, _, ast} = ast(code)

    result = AliasTransformer.transform(ast)
    expected = %Alias{module: @expected_module, as: [:Xyz]}

    assert result == expected
  end
end
