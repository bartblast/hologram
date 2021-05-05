defmodule Hologram.Compiler.PrimitiveTypeGeneratorTest do
  use ExUnit.Case, async: true
  alias Hologram.Compiler.PrimitiveTypeGenerator

  test "generator/2" do
    result = PrimitiveTypeGenerator.generate(:atom, "'test'")
    assert result == "{ type: 'atom', value: 'test' }"
  end
end
