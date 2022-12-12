defmodule Hologram.Compiler.ImportDirectiveTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.ImportDirectiveTransformer
  alias Hologram.Compiler.IR.ImportDirective

  test "without 'only' clause" do
    code = "import Abc.Bcd"
    ast = ast(code)

    result = ImportDirectiveTransformer.transform(ast)
    expected = %ImportDirective{alias_segs: [:Abc, :Bcd], module: nil, only: []}

    assert result == expected
  end

  test "with 'only' clause" do
    code = "import Abc.Bcd, only: [xyz: 2]"
    ast = ast(code)

    result = ImportDirectiveTransformer.transform(ast)
    expected = %ImportDirective{alias_segs: [:Abc, :Bcd], module: nil, only: [xyz: 2]}

    assert result == expected
  end

  test "ignores other opts" do
    code = "import Abc.Bcd, other_opt: false"
    ast = ast(code)

    result = ImportDirectiveTransformer.transform(ast)
    expected = %ImportDirective{alias_segs: [:Abc, :Bcd], module: nil, only: []}

    assert result == expected
  end
end
