defmodule Hologram.Compiler.ReflectionTest do
  use Hologram.TestCase, async: true
  alias Hologram.Compiler.Reflection

  @module_1 Hologram.Test.Fixtures.Compiler.Reflection.Module1
  @module_segs_1 [:Hologram, :Test, :Fixtures, :Compiler, :Reflection, :Module1]

  describe "module_ast/1" do
    @expected {:defmodule, [line: 1], [
        {:__aliases__, [line: 1], @module_segs_1},
        [do: {:__block__, [], []}]
      ]}

    test "module segments arg" do
      result = Reflection.module_ast(@module_segs_1)
      assert result == @expected
    end

    test "module arg" do
      result = Reflection.module_ast(@module_1)
      assert result == @expected
    end
  end

  test "source_path/1" do
    result = Reflection.source_path(Hologram.Compiler.ReflectionTest)
    expected = __ENV__.file

    assert result == expected
  end
end
