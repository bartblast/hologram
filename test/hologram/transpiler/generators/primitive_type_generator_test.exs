defmodule Hologram.Transpiler.PrimitiveTypeGeneratorTest do
  use ExUnit.Case, async: true
  alias Hologram.Transpiler.PrimitiveTypeGenerator

  test "generator/2" do
    result = PrimitiveTypeGenerator.generate(:atom, "'test'")
    assert result == "{ type: 'atom', value: 'test' }"
  end
end
