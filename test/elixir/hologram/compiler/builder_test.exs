defmodule Hologram.Compiler.BuilderTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Builder
  alias Hologram.Commons.PersistentLookupTable

  @plt_name :"plt_#{__MODULE__}"

  test "build_module_beam_defs_digest_plt/1" do
    assert plt =
             %PersistentLookupTable{name: @plt_name} =
             build_module_beam_defs_digest_plt(@plt_name)

    assert {:ok, <<_digest::256>>} = PersistentLookupTable.get(plt, Hologram.Compiler.Builder)
  end
end
