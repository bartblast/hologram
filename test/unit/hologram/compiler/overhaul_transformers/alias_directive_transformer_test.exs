defmodule Hologram.Compiler.AliasDirectiveTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.AliasDirectiveTransformer
  alias Hologram.Compiler.IR.AliasDirective

  test "default 'as' option" do
    code = "alias A.B"
    ast = ast(code)

    result = AliasDirectiveTransformer.transform(ast)
    expected = %AliasDirective{alias_segs: [:A, :B], as: :B}

    assert result == expected
  end

  test "custom 'as' option" do
    code = "alias A.B, as: C"
    ast = ast(code)

    result = AliasDirectiveTransformer.transform(ast)
    expected = %AliasDirective{alias_segs: [:A, :B], as: :C}

    assert result == expected
  end

  test "'warn' option" do
    code = "alias A.B, warn: false"
    ast = ast(code)

    result = AliasDirectiveTransformer.transform(ast)
    expected = %AliasDirective{alias_segs: [:A, :B], as: :B}

    assert result == expected
  end

  test "'as' option + 'warn' option" do
    code = "alias A.B, as: C, warn: false"

    ast = ast(code)

    result = AliasDirectiveTransformer.transform(ast)
    expected = %AliasDirective{alias_segs: [:A, :B], as: :C}

    assert result == expected
  end

  test "multi-alias without options" do
    code = "alias A.B.{C, D}"
    ast = ast(code)

    result = AliasDirectiveTransformer.transform(ast)

    expected = [
      %AliasDirective{alias_segs: [:A, :B, :C], as: :C},
      %AliasDirective{alias_segs: [:A, :B, :D], as: :D}
    ]

    assert result == expected
  end

  test "multi-alias with options" do
    code = "alias A.B.{C, D}, warn: false"

    ast = ast(code)

    result = AliasDirectiveTransformer.transform(ast)

    expected = [
      %AliasDirective{alias_segs: [:A, :B, :C], as: :C},
      %AliasDirective{alias_segs: [:A, :B, :D], as: :D}
    ]

    assert result == expected
  end
end
