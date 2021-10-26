defmodule Hologram.Compiler.AliasDirectiveTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.AliasDirectiveTransformer
  alias Hologram.Compiler.IR.AliasDirective

  @module_1 Hologram.Test.Fixtures.Compiler.AliasDirectiveTransformer.Module1
  @module_2 Hologram.Test.Fixtures.Compiler.AliasDirectiveTransformer.Module2

  test "default 'as' option" do
    code = "alias Hologram.Test.Fixtures.Compiler.AliasDirectiveTransformer.Module1"
    {:alias, _, ast} = ast(code)

    result = AliasDirectiveTransformer.transform(ast)
    expected = %AliasDirective{module: @module_1, as: [:Module1]}

    assert result == expected
  end

  test "one-part 'as' option" do
    code = "alias Hologram.Test.Fixtures.Compiler.AliasDirectiveTransformer.Module1, as: Xyz"
    {:alias, _, ast} = ast(code)

    result = AliasDirectiveTransformer.transform(ast)
    expected = %AliasDirective{module: @module_1, as: [:Xyz]}

    assert result == expected
  end

  test "multiple-part 'as' option" do
    code = "alias Hologram.Test.Fixtures.Compiler.AliasDirectiveTransformer.Module1, as: Xyz.Kmn"
    {:alias, _, ast} = ast(code)

    result = AliasDirectiveTransformer.transform(ast)
    expected = %AliasDirective{module: @module_1, as: [:Xyz, :Kmn]}

    assert result == expected
  end

  test "'warn' option" do
    code = "alias Hologram.Test.Fixtures.Compiler.AliasDirectiveTransformer.Module1, warn: false"
    {:alias, _, ast} = ast(code)

    result = AliasDirectiveTransformer.transform(ast)
    expected = %AliasDirective{module: @module_1, as: [:Module1]}

    assert result == expected
  end

  test "'as' option + 'warn' option" do
    code = "alias Hologram.Test.Fixtures.Compiler.AliasDirectiveTransformer.Module1, as: Xyz, warn: false"
    {:alias, _, ast} = ast(code)

    result = AliasDirectiveTransformer.transform(ast)
    expected = %AliasDirective{module: @module_1, as: [:Xyz]}

    assert result == expected
  end

  test "multi-alias without options" do
    code = "alias Hologram.Test.Fixtures.Compiler.AliasDirectiveTransformer.{Module1, Module2}"
    {:alias, _, ast} = ast(code)

    result = AliasDirectiveTransformer.transform(ast)

    expected = [
      %AliasDirective{module: @module_1, as: [:Module1]},
      %AliasDirective{module: @module_2, as: [:Module2]}
    ]

    assert result == expected
  end

  test "multi-alias with options" do
    code =
      "alias Hologram.Test.Fixtures.Compiler.AliasDirectiveTransformer.{Module1, Module2}, warn: false"

    {:alias, _, ast} = ast(code)

    result = AliasDirectiveTransformer.transform(ast)

    expected = [
      %AliasDirective{module: @module_1, as: [:Module1]},
      %AliasDirective{module: @module_2, as: [:Module2]}
    ]

    assert result == expected
  end
end
