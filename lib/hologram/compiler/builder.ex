defmodule Hologram.Compiler.Builder do
  alias Hologram.Commons.PersistentLookupTable, as: PLT
  alias Hologram.Compiler.IR
  alias Hologram.Compiler.Reflection

  @doc """
  Builds a persistent lookup table (PLT) containing the BEAM defs digests for all the modules in the project.

  ## Examples

      iex> build_module_digest_plt(:abc)
      %Hologram.Commons.PersistentLookupTable{
        pid: #PID<0.251.0>,
        name: :plt_abc
      }
  """
  @spec build_module_digest_plt(atom) :: PLT.t()
  def build_module_digest_plt(name) do
    plt = PLT.start(name: name)

    Reflection.list_loaded_otp_apps()
    |> Kernel.--([:hex])
    |> Reflection.list_elixir_modules()
    |> Enum.each(&rebuild_module_digest_plt_entry(plt, &1))

    plt
  end

  def diff_module_digest_plts(old_plt, new_plt) do
    old_mapset = mapset_from_plt(old_plt)
    new_mapset = mapset_from_plt(new_plt)

    removed_modules =
      old_mapset
      |> MapSet.difference(new_mapset)
      |> MapSet.to_list()

    added_modules =
      new_mapset
      |> MapSet.difference(old_mapset)
      |> MapSet.to_list()

    updated_modules =
      old_mapset
      |> MapSet.intersection(new_mapset)
      |> MapSet.to_list()
      |> Enum.filter(&(PLT.get(old_plt, &1) != PLT.get(new_plt, &1)))

    %{
      added_modules: added_modules,
      removed_modules: removed_modules,
      updated_modules: updated_modules
    }
  end

  @doc """
  Given a diff of changes, updates the IR persistent lookup table (PLT)
  by deleting entries for modules that have been removed,
  rebuilding the IR of modules that have been updated,
  and adding the IR of new modules.

  ## Examples

      iex> plt = %PersistentLookupTable{
        pid: #PID<0.251.0>,
        name: :plt_abc
      }
      iex> diff = %{
      ...>   added_modules: [Module1, Module2],
      ...>   removed_modules: [Module5, Module6],
      ...>   updated_modules: [Module3, Module4]
      ...> }
      iex> patch_ir_plt(plt, diff)
      %PersistentLookupTable{
        pid: #PID<0.251.0>,
        name: :plt_abc
      }
  """
  @spec patch_ir_plt(PLT.t(), map) :: PLT.t()
  def patch_ir_plt(ir_plt, diff) do
    Enum.each(diff.removed_modules, &PLT.delete(ir_plt, &1))
    Enum.each(diff.updated_modules, &rebuild_ir_plt_entry(ir_plt, &1))
    Enum.each(diff.added_modules, &rebuild_ir_plt_entry(ir_plt, &1))
    ir_plt
  end

  defp mapset_from_plt(plt) do
    plt
    |> PLT.get_all()
    |> Map.keys()
    |> MapSet.new()
  end

  defp rebuild_ir_plt_entry(plt, module) do
    PLT.put(plt, module, IR.for_module(module))
  end

  defp rebuild_module_digest_plt_entry(plt, module) do
    data =
      module
      |> Reflection.module_beam_defs()
      |> :erlang.term_to_binary(compressed: 0)

    digest = :crypto.hash(:sha256, data)

    PLT.put(plt.name, module, digest)
  end
end
