defmodule Hologram.Compiler.BuilderTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Builder
  alias Hologram.Commons.PersistentLookupTable, as: PLT

  @plt_name :"plt_#{__MODULE__}"

  test "build_module_beam_defs_digest_plt/1" do
    assert plt = %PLT{name: @plt_name} = build_module_beam_defs_digest_plt(@plt_name)

    assert {:ok, <<_digest::256>>} = PLT.get(plt, Hologram.Compiler.Builder)
  end

  describe "diff_module_beam_defs_digest_plts/2" do
    setup do
      old_plt = PLT.start(name: :"old_#{@plt_name}")
      PLT.put(old_plt, :module_1, :digest_1)
      PLT.put(old_plt, :module_3, :digest_3a)
      PLT.put(old_plt, :module_5, :digest_5)
      PLT.put(old_plt, :module_6, :digest_6a)
      PLT.put(old_plt, :module_7, :digest_7)

      new_plt = PLT.start(name: :"new_#{@plt_name}")
      PLT.put(new_plt, :module_1, :digest_1)
      PLT.put(new_plt, :module_2, :digest_2)
      PLT.put(new_plt, :module_3, :digest_3b)
      PLT.put(new_plt, :module_4, :digest_4)
      PLT.put(new_plt, :module_6, :digest_6b)

      [
        old_plt: old_plt,
        new_plt: new_plt
      ]
    end

    test "added modules", %{old_plt: old_plt, new_plt: new_plt} do
      assert %{added_modules: [:module_2, :module_4]} =
               diff_module_beam_defs_digest_plts(old_plt, new_plt)
    end

    test "removed modules", %{old_plt: old_plt, new_plt: new_plt} do
      assert %{removed_modules: [:module_5, :module_7]} =
               diff_module_beam_defs_digest_plts(old_plt, new_plt)
    end

    test "updated modules", %{old_plt: old_plt, new_plt: new_plt} do
      assert %{updated_modules: [:module_3, :module_6]} =
               diff_module_beam_defs_digest_plts(old_plt, new_plt)
    end
  end
end
