defmodule Hologram.Compiler.ModuleTypeTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, ModuleTypeTransformer}
  alias Hologram.Compiler.IR.{Alias, ModuleType}

  test "non-aliased module segments" do
    code = "Abc.Bcd"
    ast = ast(code)

    result = ModuleTypeTransformer.transform(ast, %Context{})
    expected = %ModuleType{module: Abc.Bcd}

    assert result == expected
  end

  test "aliased module segments" do
    aliases = [%Alias{module: Abc.Bcd, as: [:Bcd]}]
    context = %Context{aliases: aliases}

    code = "Bcd"
    ast = ast(code)

    result = ModuleTypeTransformer.transform(ast, context)
    expected = %ModuleType{module: Abc.Bcd}

    assert result == expected
  end

  test "module atom" do
    result = ModuleTypeTransformer.transform(Abc.Bcd, %Context{})
    expected = %ModuleType{module: Abc.Bcd}

    assert result == expected
  end
end
