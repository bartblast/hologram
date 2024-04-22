defmodule Hologram.Benchmarks do
  alias Hologram.Commons.PLT
  alias Hologram.Commons.Reflection
  alias Hologram.Commons.TaskUtils
  alias Hologram.Compiler.IR

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

  @doc """
  Builds IR persistent lookup table (PLT).
  """
  @spec build_ir_plt(PLT.t()) :: PLT.t()
  def build_ir_plt(module_beam_path_plt) do
    ir_plt = PLT.start()

    Reflection.list_elixir_modules()
    |> TaskUtils.async_many(fn module ->
      beam_path = PLT.get!(module_beam_path_plt, module)
      ir = IR.for_module(beam_path)
      PLT.put(ir_plt, module, ir)
    end)
    |> Task.await_many(:infinity)

    ir_plt
  end
end
