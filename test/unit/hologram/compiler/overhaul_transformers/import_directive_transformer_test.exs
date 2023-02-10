defmodule Hologram.Compiler.ImportDirectiveTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.ImportDirectiveTransformer
  alias Hologram.Compiler.IR.ImportDirective

  test "without opts" do
    code = "import Abc.Bcd"
    ast = ast(code)

    result = ImportDirectiveTransformer.transform(ast)
    expected = %ImportDirective{alias_segs: [:Abc, :Bcd], only: [], except: []}

    assert result == expected
  end

  test "with 'only' opt" do
    code = "import Abc.Bcd, only: [xyz: 2]"
    ast = ast(code)

    result = ImportDirectiveTransformer.transform(ast)
    expected = %ImportDirective{alias_segs: [:Abc, :Bcd], only: [xyz: 2], except: []}

    assert result == expected
  end

  test "with 'except' opt" do
    code = "import Abc.Bcd, except: [xyz: 2]"
    ast = ast(code)

    result = ImportDirectiveTransformer.transform(ast)
    expected = %ImportDirective{alias_segs: [:Abc, :Bcd], only: [], except: [xyz: 2]}

    assert result == expected
  end

  test "with both 'only' and 'except' opts" do
    code = "import Abc.Bcd, only: [abc: 1], except: [xyz: 2]"
    ast = ast(code)

    result = ImportDirectiveTransformer.transform(ast)
    expected = %ImportDirective{alias_segs: [:Abc, :Bcd], only: [abc: 1], except: [xyz: 2]}

    assert result == expected
  end

  test "with invalid opt" do
    code = "import Abc.Bcd, other_opt: false"
    ast = ast(code)

    result = ImportDirectiveTransformer.transform(ast)
    expected = %ImportDirective{alias_segs: [:Abc, :Bcd], only: [], except: []}

    assert result == expected
  end
end
