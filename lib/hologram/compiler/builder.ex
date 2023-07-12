defmodule Hologram.Compiler.Builder do
  alias Hologram.Commons.PersistentLookupTable, as: PLT
  alias Hologram.Compiler.Reflection

  @doc """
  Builds a persistent lookup table (PLT) containing the BEAM defs digests for all the modules in the project.

  ## Examples

      iex> build_module_beam_defs_digest_plt(:abc)
      %Hologram.Commons.PersistentLookupTable{
        pid: #PID<0.251.0>,
        name: :plt_abc
      }

  """
  @spec build_module_beam_defs_digest_plt(atom) :: PLT.t()
  def build_module_beam_defs_digest_plt(name) do
    plt = PLT.start(name: name)

    Reflection.list_loaded_otp_apps()
    |> Kernel.--([:hex])
    |> Reflection.list_elixir_modules()
    # TODO: remove this line once https://github.com/hrzndhrn/beam_file/issues/13 is fixed
    |> Kernel.--([Mix.Compilers.Test, Mix.Release, Protocol])
    |> Enum.each(&put_module_beam_defs_digest_to_plt(plt, &1))

    plt
  end

  def diff_module_beam_defs_digest_plts(old_plt, new_plt) do
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

  defp mapset_from_plt(plt) do
    plt
    |> PLT.get_all()
    |> Map.keys()
    |> MapSet.new()
  end

  defp put_module_beam_defs_digest_to_plt(plt, module) do
    data =
      module
      |> Reflection.module_beam_defs()
      |> :erlang.term_to_binary(compressed: 0)

    digest = :crypto.hash(:sha256, data)

    PLT.put(plt.name, module, digest)
  end
end
