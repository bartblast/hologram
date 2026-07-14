defmodule Mix.Tasks.Holo.Compiler.RuntimeToMfaPaths do
  @moduledoc """
  Prints paths from runtime entry MFAs to the given destination MFA.

  ## Examples

      $ mix holo.compiler.runtime_to_mfa_paths "{MyModule, :my_fun, 2}"

  Where `{MyModule, :my_fun, 2}` is the destination MFA.
  """

  use Mix.Task

  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Digraph
  alias Hologram.Reflection

  @requirements ["app.config"]

  @doc false
  @impl Mix.Task
  def run([dest_mfa_code]) do
    {dest_mfa, _binding} = Code.eval_string(dest_mfa_code)

    call_graph = CallGraph.remove_manually_ported_mfas(Compiler.build_call_graph())
    runtime_mfas = CallGraph.list_runtime_mfas(call_graph, Reflection.list_pages())

    if dest_mfa in runtime_mfas do
      print_runtime_mfa_paths(call_graph, dest_mfa)
    end

    :ok
  end

  defp print_runtime_mfa_paths(call_graph, dest_mfa) do
    graph = CallGraph.get_graph(call_graph)

    Enum.each(CallGraph.list_runtime_entry_mfas(), fn entry_mfa ->
      print_shortest_path(graph, entry_mfa, dest_mfa)
    end)
  end

  defp print_shortest_path(graph, entry_mfa, dest_mfa) do
    case Digraph.shortest_path(graph, entry_mfa, dest_mfa) do
      nil ->
        :ok

      shortest_path ->
        # credo:disable-for-next-line Credo.Check.Refactor.IoPuts
        IO.puts("\n#{inspect(entry_mfa)} -> #{inspect(dest_mfa)}\n#{inspect(shortest_path)}\n")
    end
  end
end
