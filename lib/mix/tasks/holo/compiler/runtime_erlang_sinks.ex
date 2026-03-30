defmodule Mix.Tasks.Holo.Compiler.RuntimeErlangSinks do
  @moduledoc """
  For each Erlang MFA reachable from the runtime entry points, prints how many
  MFAs transitively call it (biggest sinks first).

  Only direct function-to-function edges are followed (module vertices are skipped),
  so module-to-function-definition edges do not inflate the counts.

  ## Examples

      $ mix holo.compiler.runtime_erlang_sinks
  """

  use Mix.Task

  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Digraph
  alias Hologram.Reflection

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
    IO.puts("#{length(sinks)} Erlang MFA sinks in runtime:\n")

    Enum.each(sinks, fn {{module, function, arity}, count} ->
      IO.puts(":#{module}.#{function}/#{arity} - #{count} MFAs reaching")
    end)

    :ok
  end
end
