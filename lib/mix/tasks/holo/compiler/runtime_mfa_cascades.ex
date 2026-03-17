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

    # For each module vertex, find incoming edges from reachable MFAs
    # and count downstream MFAs
    cascades =
      module_vertices
      |> Enum.flat_map(fn module ->
        downstream_mfa_count =
          graph
          |> Digraph.reachable([module])
          |> Enum.count(&match?({_module, _function, _arity}, &1))

        graph
        |> Digraph.incoming_edges(module)
        |> Enum.map(&elem(&1, 0))
        |> Enum.filter(&MapSet.member?(reachable, &1))
        |> Enum.map(fn source -> {source, module, downstream_mfa_count} end)
      end)
      |> Enum.sort_by(fn {_source, _module, count} -> count end, :desc)

    # credo:disable-for-lines:5 Credo.Check.Refactor.IoPuts
    IO.puts("#{length(cascades)} edges to module vertices:\n")

    Enum.each(cascades, fn {source, module, count} ->
      IO.puts("#{inspect(source)} -> #{inspect(module)} (#{count} MFAs reachable)")
    end)

    :ok
  end
end
