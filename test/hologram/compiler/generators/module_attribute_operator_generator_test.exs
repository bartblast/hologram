defmodule Hologram.Compiler.ModuleAttributeOperatorGeneratorTest do
  use Hologram.TestCase, async: true
  alias Hologram.Compiler.{Context, ModuleAttributeOperatorGenerator}

  test "generate/2" do
    result = ModuleAttributeOperatorGenerator.generate(:xyz, %Context{})
    expected = "$state.data['~atom[xyz]']"

    assert result == expected
  end
end
