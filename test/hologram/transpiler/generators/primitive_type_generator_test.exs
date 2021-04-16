defmodule Hologram.Transpiler.Generators.PrimitiveTypeGeneratorTest do
  use ExUnit.Case, async: true
  alias Hologram.Transpiler.Generators.PrimitiveTypeGenerator

  test "generator/2" do
    result = PrimitiveTypeGenerator.generate(:atom, "'test'")
    assert result == "{ type: 'atom', value: 'test' }"
  end
end
