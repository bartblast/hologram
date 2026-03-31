defmodule Mix.Tasks.Holo.Compiler.RuntimeMfaCascades do
  @moduledoc """
  Prints edges to module vertices in the runtime call graph, sorted by the number
  of transitively reachable MFAs from each module vertex (biggest cascades first).
  """

  use Mix.Task

  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Digraph

  @requirements ["app.config"]

  @doc false
  @impl Mix.Task
  def run(_args) do
    graph =
      Compiler.build_call_graph()
      |> CallGraph.remove_manually_ported_mfas()
      |> CallGraph.remove_server_only_mfas!()
      |> CallGraph.get_graph()

    entry_mfas = CallGraph.list_runtime_entry_mfas()

    reachable =
      graph
      |> Digraph.reachable(entry_mfas)
      |> MapSet.new()

    module_vertices =
      reachable
      |> Enum.filter(&is_atom/1)
      |> MapSet.new()

    cascades = CallGraph.compute_cascades(graph, module_vertices, reachable)

    # credo:disable-for-lines:5 Credo.Check.Refactor.IoPuts
    IO.puts("#{length(cascades)} edges to module vertices:\n")

    Enum.each(cascades, fn {source, module, count} ->
      IO.puts("#{inspect(source)} -> #{inspect(module)} (#{count} MFAs reachable)")
    end)

    :ok
  end
end
