defmodule Hologram.Compiler.ReflectionTest do
  use Hologram.TestCase, async: true
  alias Hologram.Compiler.Reflection

  test "source_path/1" do
    result = Reflection.source_path(Hologram.Compiler.ReflectionTest)
    expected = __ENV__.file

    assert result == expected
  end
end
