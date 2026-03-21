defmodule Mix.Tasks.Holo.Compiler.PageMfaCascades do
  @moduledoc """
  Prints edges to module vertices in the given page's call graph, sorted by the number
  of transitively reachable MFAs from each module vertex (biggest cascades first).

  The call graph is prepared the same way as during compilation: manually ported MFAs
  and runtime MFAs are removed first, so only page-specific cascades are shown.

  ## Examples

      $ mix holo.compiler.page_mfa_cascades MyPageModule

  Where `MyPageModule` is the name of the page module you want to analyze (without the `Elixir.` prefix).
  """

  use Mix.Task

  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Digraph

  @requirements ["app.config"]

  @doc false
  @impl Mix.Task
  def run([page_module_name]) do
    page_module = String.to_existing_atom("Elixir." <> page_module_name)

    call_graph = Compiler.build_call_graph()

    call_graph_for_runtime =
      call_graph
      |> CallGraph.clone()
      |> CallGraph.remove_manually_ported_mfas()

    runtime_mfas = CallGraph.list_runtime_mfas(call_graph_for_runtime)
    call_graph_for_pages = CallGraph.remove_runtime_mfas!(call_graph_for_runtime, runtime_mfas)

    graph = CallGraph.get_pruned_page_graph(call_graph_for_pages, page_module)

    reachable =
      graph
      |> Digraph.reachable([page_module])
      |> MapSet.new()

    module_vertices =
      reachable
      |> Enum.filter(&is_atom/1)
      |> MapSet.new()

    cascades = CallGraph.compute_cascades(graph, module_vertices, reachable)

    # credo:disable-for-lines:5 Credo.Check.Refactor.IoPuts
    IO.puts("#{length(cascades)} edges to module vertices for #{inspect(page_module)}:\n")

    Enum.each(cascades, fn {source, module, count} ->
      IO.puts("#{inspect(source)} -> #{inspect(module)} (#{count} MFAs reachable)")
    end)

    :ok
  end
end
