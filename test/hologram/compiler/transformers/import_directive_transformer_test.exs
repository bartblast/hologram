defmodule Hologram.Compiler.ImportDirectiveTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.ImportDirectiveTransformer
  alias Hologram.Compiler.IR.ImportDirective

  @expected_module Hologram.Test.Fixtures.Compiler.Transformer.Module1

  test "without 'only' clause" do
    code = "import Hologram.Test.Fixtures.Compiler.Transformer.Module1"
    {:import, _, ast} = ast(code)

    result = ImportDirectiveTransformer.transform(ast)
    expected = %ImportDirective{module: @expected_module, only: []}

    assert result == expected
  end

  test "with 'only' clause" do
    code = "import Hologram.Test.Fixtures.Compiler.Transformer.Module1, only: [abc: 2]"
    {:import, _, ast} = ast(code)

    result = ImportDirectiveTransformer.transform(ast)
    expected = %ImportDirective{module: @expected_module, only: [abc: 2]}

    assert result == expected
  end

  test "ignores other opts" do
    code = "import Hologram.Test.Fixtures.Compiler.Transformer.Module1, warn: false"
    {:import, _, ast} = ast(code)

    result = ImportDirectiveTransformer.transform(ast)
    expected = %ImportDirective{module: @expected_module, only: []}

    assert result == expected
  end
end
