defmodule Hologram.Compiler.ModuleTypeTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, ModuleTypeTransformer}
  alias Hologram.Compiler.IR.ModuleType

  test "alias segments" do
    code = "Abc.Bcd"
    ast = ast(code)

    result = ModuleTypeTransformer.transform(ast, %Context{})
    expected = %ModuleType{alias_segs: [:Abc, :Bcd], module: nil}

    assert result == expected
  end

  test "alias atom" do
    result = ModuleTypeTransformer.transform(Abc.Bcd, %Context{})
    expected = %ModuleType{alias_segs: [:Abc, :Bcd], module: nil}

    assert result == expected
  end
end
