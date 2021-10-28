defmodule Hologram.Compiler.Traverser.CommonsTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.ModuleDefinition
  alias Hologram.Compiler.Traverser.Commons
  alias Hologram.Test.Fixtures.PlaceholderModule

  describe "maybe_add_module_def/2" do
    test "non standard lib module that isn't in the map yet is added" do
      result = Commons.maybe_add_module_def(%{}, PlaceholderModule)

      assert Map.keys(result) == [PlaceholderModule]
      assert %ModuleDefinition{} = result[PlaceholderModule]
    end

    test "module that is in the map already is ignored" do
      result =
        Commons.maybe_add_module_def(%{}, PlaceholderModule)
        |> Commons.maybe_add_module_def(PlaceholderModule)

      assert Map.keys(result) == [PlaceholderModule]
      assert %ModuleDefinition{} = result[PlaceholderModule]
    end

    test "standard lib module is ignored" do
      result = Commons.maybe_add_module_def(%{}, Kernel)
      assert result == %{}
    end
  end
end
