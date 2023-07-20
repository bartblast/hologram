defmodule Hologram.Compiler.BuilderTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Builder

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.IR
  alias Hologram.Test.Fixtures.Compiler.Builder.Module1
  alias Hologram.Test.Fixtures.Compiler.Builder.Module2
  alias Hologram.Test.Fixtures.Compiler.Builder.Module3
  alias Hologram.Test.Fixtures.Compiler.Builder.Module4

  @plt_name_1 :"plt_#{__MODULE__}_1"
  @plt_name_2 :"plt_#{__MODULE__}_2"

  setup do
    wait_for_plt_cleanup(@plt_name_1)
    wait_for_plt_cleanup(@plt_name_2)
    :ok
  end

  test "build_module_digest_plt/1" do
    assert %PLT{name: @plt_name_1} = plt = build_module_digest_plt(@plt_name_1)

    assert {:ok, <<_digest::256>>} = PLT.get(plt, Hologram.Compiler.Builder)
  end

  describe "diff_module_digest_plts/2" do
    setup do
      old_plt = PLT.start(name: @plt_name_1)
      PLT.put(old_plt, :module_1, :digest_1)
      PLT.put(old_plt, :module_3, :digest_3a)
      PLT.put(old_plt, :module_5, :digest_5)
      PLT.put(old_plt, :module_6, :digest_6a)
      PLT.put(old_plt, :module_7, :digest_7)

      new_plt = PLT.start(name: @plt_name_2)
      PLT.put(new_plt, :module_1, :digest_1)
      PLT.put(new_plt, :module_2, :digest_2)
      PLT.put(new_plt, :module_3, :digest_3b)
      PLT.put(new_plt, :module_4, :digest_4)
      PLT.put(new_plt, :module_6, :digest_6b)

      [result: diff_module_digest_plts(old_plt, new_plt)]
    end

    test "added modules", %{result: result} do
      assert %{added_modules: [:module_2, :module_4]} = result
    end

    test "removed modules", %{result: result} do
      assert %{removed_modules: [:module_5, :module_7]} = result
    end

    test "updated modules", %{result: result} do
      assert %{updated_modules: [:module_3, :module_6]} = result
    end
  end

  describe "patch_ir_plt/2" do
    setup do
      plt = PLT.start(name: @plt_name_1)
      PLT.put(plt, :module_5, :ir_5)
      PLT.put(plt, :module_6, :ir_6)
      PLT.put(plt, Module3, :ir_3)
      PLT.put(plt, :module_7, :ir_7)
      PLT.put(plt, :module_8, :ir_8)
      PLT.put(plt, Module4, :ir_4)

      diff = %{
        added_modules: [Module1, Module2],
        removed_modules: [:module_5, :module_7],
        updated_modules: [Module3, Module4]
      }

      patch_ir_plt(plt, diff)

      [plt: plt]
    end

    test "adds entries of added modules", %{plt: plt} do
      assert PLT.get(plt, Module1) ==
               {:ok,
                %IR.ModuleDefinition{
                  module: %IR.AtomType{
                    value: Module1
                  },
                  body: %IR.Block{expressions: []}
                }}

      assert PLT.get(plt, Module2) ==
               {:ok,
                %IR.ModuleDefinition{
                  module: %IR.AtomType{
                    value: Module2
                  },
                  body: %IR.Block{expressions: []}
                }}
    end

    test "removes entries of removed modules", %{plt: plt} do
      assert PLT.get(plt, :module_5) == :error
      assert PLT.get(plt, :module_7) == :error
    end

    test "updates entries of updated modules", %{plt: plt} do
      assert PLT.get(plt, Module3) ==
               {:ok,
                %IR.ModuleDefinition{
                  module: %IR.AtomType{
                    value: Module3
                  },
                  body: %IR.Block{expressions: []}
                }}

      assert PLT.get(plt, Module4) ==
               {:ok,
                %IR.ModuleDefinition{
                  module: %IR.AtomType{
                    value: Module4
                  },
                  body: %IR.Block{expressions: []}
                }}
    end

    test "doesn't change entries of unchanged modules", %{plt: plt} do
      assert PLT.get(plt, :module_6) == {:ok, :ir_6}
      assert PLT.get(plt, :module_8) == {:ok, :ir_8}
    end
  end
end
