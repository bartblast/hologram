defmodule Hologram.Compiler.ModuleAttributeOperatorGeneratorTest do
  use Hologram.TestCase, async: true
  alias Hologram.Compiler.{Context, ModuleAttributeOperatorGenerator}

  test "generate/2" do
    context = %Context{module: [], uses: [], imports: [], aliases: [], attributes: []}

    result = ModuleAttributeOperatorGenerator.generate(:xyz, context)
    expected = "$state.data['~atom[xyz]']"

    assert result == expected
  end
end
