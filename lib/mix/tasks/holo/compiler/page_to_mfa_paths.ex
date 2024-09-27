defmodule Mix.Tasks.Holo.Compiler.PageToMfaPaths do
  @moduledoc """
  Prints paths from page entry MFAs to the given destination MFA.
  """

  use Mix.Task

  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph

  @requirements ["app.config"]

  @doc false
  @impl Mix.Task
  def run([page_module_arg, dest_mfa_arg]) do
    page_module = String.to_existing_atom("Elixir." <> page_module_arg)
    {dest_mfa, _binding} = Code.eval_string(dest_mfa_arg)

    graph =
      Compiler.build_call_graph()
      |> CallGraph.remove_manually_ported_mfas()
      |> remove_runtime_mfas()
      |> CallGraph.get_graph()

    page_module
    |> CallGraph.list_page_entry_mfas()
    |> Enum.each(fn entry_mfa ->
      shortest_path = Graph.get_shortest_path(graph, entry_mfa, dest_mfa)

      if shortest_path do
        # credo:disable-for-next-line Credo.Check.Refactor.IoPuts
        IO.puts("\n#{inspect(entry_mfa)} -> #{inspect(dest_mfa)}\n#{inspect(shortest_path)}\n")
      end
    end)

    :ok
  end

  defp remove_runtime_mfas(call_graph) do
    runtime_mfas = CallGraph.list_runtime_mfas(call_graph)
    CallGraph.remove_runtime_mfas!(call_graph, runtime_mfas)
  end
end
