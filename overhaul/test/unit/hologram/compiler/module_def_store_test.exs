defmodule Hologram.Compiler.ModuleDefStoreTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.{ModuleDefStore, ModuleDefStoreTest}
  alias Hologram.Compiler.IR.ModuleDefinition

  setup do
    ModuleDefStore.run()
    :ok
  end

  describe "get_if_not_exists/1 (and handle_call/3 :get_if_not_exists implicitely)" do
    test "module is not in store yet" do
      assert %ModuleDefinition{module: ModuleDefStoreTest} =
               ModuleDefStore.get_if_not_exists(ModuleDefStoreTest)
    end

    test "module is in store already" do
      ModuleDefStore.put(:test_module, %ModuleDefinition{module: :test_module})
      refute ModuleDefStore.get_if_not_exists(:test_module)
    end
  end
end
