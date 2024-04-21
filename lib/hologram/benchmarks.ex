defmodule Hologram.Benchmarks do
  alias Hologram.Commons.PLT
  alias Hologram.Commons.Reflection
  alias Hologram.Commons.TaskUtils

  @doc """
  Builds module BEAM path persistent lookup table (PLT).
  """
  @spec build_module_beam_path_plt :: PLT.t()
  def build_module_beam_path_plt do
    module_beam_path_plt = PLT.start()

    Reflection.list_elixir_modules()
    |> TaskUtils.async_many(fn module ->
      beam_path = :code.which(module)
      PLT.put(module_beam_path_plt, module, beam_path)
    end)
    |> Task.await_many(:infinity)

    module_beam_path_plt
  end
end
