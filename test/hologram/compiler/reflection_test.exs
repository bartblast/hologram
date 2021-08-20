defmodule Hologram.Compiler.ReflectionTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{MacroDefinition, ModuleDefinition, UseDirective}
  alias Hologram.Compiler.Reflection

  @module_1 Hologram.Test.Fixtures.Compiler.Reflection.Module1
  @module_2 Hologram.Test.Fixtures.Compiler.Reflection.Module2
  @module_segs_1 [:Hologram, :Test, :Fixtures, :Compiler, :Reflection, :Module1]

  test "macro_definition/3" do
    result = Reflection.macro_definition(@module_2, :test_macro, [1, 2])
    assert %MacroDefinition{arity: 2, name: :test_macro} = result
  end

  describe "module_ast/1" do
    @expected {:defmodule, [line: 1], [
        {:__aliases__, [line: 1], @module_segs_1},
        [do: {:__block__, [], []}]
      ]}

    test "module segments arg" do
      result = Reflection.ast(@module_segs_1)
      assert result == @expected
    end

    test "module arg" do
      result = Reflection.ast(@module_1)
      assert result == @expected
    end
  end

  test "module_definition/1" do
    result = Reflection.module_definition(@module_1)
    expected = %ModuleDefinition{module: @module_1}
    assert result == expected
  end

  test "source_path/1" do
    result = Reflection.source_path(Hologram.Compiler.ReflectionTest)
    expected = __ENV__.file

    assert result == expected
  end

  describe "standard_lib?/1" do
    test "standard lib module" do
      assert Reflection.standard_lib?(Map)
    end

    test "lib module" do
      refute Reflection.standard_lib?(Hologram.E2E.Page1)
    end

    test "deps module" do
      refute Reflection.standard_lib?(Phoenix)
    end

    test "test module" do
      refute Reflection.standard_lib?(Hologram.Compiler.ReflectionTest)
    end
  end

  describe "templatable/1" do
    test "page" do
      module_def = %ModuleDefinition{uses: [%UseDirective{module: Hologram.Page}]}
      assert Reflection.templatable?(module_def)
    end

    test "component" do
      module_def = %ModuleDefinition{uses: [%UseDirective{module: Hologram.Component}]}
      assert Reflection.templatable?(module_def)
    end

    test "other modules" do
      module_def = %ModuleDefinition{uses: []}
      refute Reflection.templatable?(module_def)
    end
  end
end
