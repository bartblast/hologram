defmodule Hologram.Compiler.ModuleTypeTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, ModuleTypeTransformer}
  alias Hologram.Compiler.IR.{Alias, ModuleType}

  test "not aliased" do
    module_segs = [:Abc, :Bcd]
    context = %Context{aliases: []}

    result = ModuleTypeTransformer.transform(module_segs, context)
    expected = %ModuleType{module: Abc.Bcd}

    assert result == expected
  end

  test "aliased" do
    module_segs = [:Bcd]
    aliases = [%Alias{module: Abc.Bcd, as: [:Bcd]}]
    context = %Context{aliases: aliases}

    result = ModuleTypeTransformer.transform(module_segs, context)
    expected = %ModuleType{module: Abc.Bcd}

    assert result == expected
  end

end
