defmodule Mix.Tasks.Holo.Compiler.RuntimeToMfaPaths do
  @moduledoc """
  Prints paths from runtime entry MFAs to the given destination MFA.
  """

  use Mix.Task

  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph

  @requirements ["app.config"]

  @doc false
  @impl Mix.Task
  def run([dest_mfa_code]) do
    {dest_mfa, _binding} = Code.eval_string(dest_mfa_code)

    graph =
      Compiler.build_call_graph()
      |> CallGraph.remove_manually_ported_mfas()
      |> CallGraph.get_graph()

    Enum.each(CallGraph.list_runtime_entry_mfas(), fn entry_mfa ->
      shortest_path = Graph.get_shortest_path(graph, entry_mfa, dest_mfa)

      if shortest_path do
        # credo:disable-for-next-line Credo.Check.Refactor.IoPuts
        IO.puts("\n#{inspect(entry_mfa)} -> #{inspect(dest_mfa)}\n#{inspect(shortest_path)}\n")
      end
    end)

    :ok
  end
end
