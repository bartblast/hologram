defmodule Mix.Tasks.Holo.Compiler.ExRuntimeMfas do
  @moduledoc """
  Prints the list of automatically transpiled Elixir MFAs used by the Hologram client runtime
  (manually ported Elixir MFAs are excluded).
  """

  use Mix.Task

  alias Hologram.Commons.PLT
  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.DataFlow
  alias Hologram.Reflection

  @requirements ["app.config"]

  @doc false
  @impl Mix.Task
  def run(_args) do
    call_graph = CallGraph.remove_manually_ported_mfas(Compiler.build_call_graph())

    module_info_plt = CallGraph.module_info_plt(call_graph)
    page_modules = Compiler.list_pages(module_info_plt)

    # What the compiler ships: the server types the data flow finds (see Hologram.Compiler.DataFlow).
    flow = DataFlow.start(PLT.start(), module_info_plt)

    mfas =
      call_graph
      |> CallGraph.list_runtime_mfas(page_modules, flow: flow)
      |> Enum.filter(fn {module, _fun, _arity} -> Reflection.elixir_module?(module) end)

    # credo:disable-for-lines:2 /Credo.Check.Refactor.IoPuts|Credo.Check.Warning.IoInspect/
    IO.puts("#{Enum.count(mfas)} MFAs found:\n")
    IO.inspect(mfas, limit: :infinity)
  end
end
