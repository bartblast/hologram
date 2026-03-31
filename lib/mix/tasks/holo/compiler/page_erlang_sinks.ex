defmodule Mix.Tasks.Holo.Compiler.PageErlangSinks do
  @moduledoc """
  For each Erlang MFA reachable from the given page, prints how many
  MFAs transitively call it (biggest sinks first).

  The call graph is prepared the same way as during compilation: manually ported MFAs
  and runtime MFAs are removed first, so only page-specific sinks are shown.

  Only direct function-to-function edges are followed (module vertices are skipped),
  so module-to-function-definition edges do not inflate the counts.

  ## Examples

      $ mix holo.compiler.page_erlang_sinks MyPageModule

  Where `MyPageModule` is the name of the page module you want to analyze (without the `Elixir.` prefix).
  """

  use Mix.Task

  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Digraph
  alias Hologram.Reflection

  @requirements ["app.config"]

  @doc false
  @impl Mix.Task
  def run([page_module_name]) do
    page_module = String.to_existing_atom("Elixir." <> page_module_name)
    call_graph = CallGraph.remove_manually_ported_mfas(Compiler.build_call_graph())
    runtime_mfas = CallGraph.list_runtime_mfas(call_graph)

    graph =
      call_graph
      |> CallGraph.remove_runtime_mfas!(runtime_mfas)
      |> CallGraph.remove_other_pages_mfas!(page_module)
      |> CallGraph.get_graph()

    reachable =
      graph
      |> Digraph.reachable([page_module])
      |> MapSet.new()

    erlang_mfas =
      reachable
      |> Enum.filter(fn
        {module, _function, _arity} -> Reflection.erlang_module?(module)
        _module -> false
      end)
      |> Enum.sort()

    sinks =
      erlang_mfas
      |> Enum.map(fn mfa ->
        reaching_count =
          graph
          |> Digraph.reaching([mfa], skip_module_vertices: true)
          |> Enum.count(fn
            {_module, _function, _arity} = vertex -> MapSet.member?(reachable, vertex)
            _module -> false
          end)

        {mfa, reaching_count}
      end)
      |> Enum.sort_by(fn {_mfa, count} -> count end, :desc)

    # credo:disable-for-lines:5 Credo.Check.Refactor.IoPuts
    IO.puts("#{length(sinks)} Erlang MFA sinks for #{inspect(page_module)}:\n")

    Enum.each(sinks, fn {{module, function, arity}, count} ->
      IO.puts(":#{module}.#{function}/#{arity} - #{count} MFAs reaching")
    end)

    :ok
  end
end
