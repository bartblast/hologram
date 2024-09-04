defmodule Mix.Tasks.Holo.Compiler.ExRuntimeMfas do
  @moduledoc """
  Prints the list of automatically transpiled Elixir MFAs used by the Hologram client runtime
  (manually ported Elixir MFAs are excluded).
  """

  use Mix.Task

  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Reflection

  @requirements ["app.config"]

  @doc false
  @impl Mix.Task
  def run(_args) do
    mfas =
      Compiler.build_call_graph()
      |> CallGraph.remove_manually_ported_mfas()
      |> CallGraph.list_runtime_mfas()
      |> Enum.filter(fn {module, _fun, _arity} -> Reflection.elixir_module?(module) end)

    # credo:disable-for-lines:2 /Credo.Check.Refactor.IoPuts|Credo.Check.Warning.IoInspect/
    IO.puts("#{Enum.count(mfas)} MFAs found:\n")
    IO.inspect(mfas, limit: :infinity)
  end
end
