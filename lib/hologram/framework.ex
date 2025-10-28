defmodule Hologram.Framework do
  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Reflection

  @elixir_stdlib_module_groups [
    {"Core",
     [
       Kernel
     ]},
    {"Data Types",
     [
       Atom,
       Base,
       Bitwise,
       Date
     ]}
  ]

  @doc """
  Returns Erlang dependencies for Elixir standard library modules.

  Analyzes the call graph of selected Elixir standard library modules and identifies
  which Erlang functions they depend on. Manually ported functions are excluded.

  ## Return Structure

  Returns a three-level nested map:
  - **Level 1**: Group name (string) -> modules in that group
  - **Level 2**: Module (atom) -> functions in that module  
  - **Level 3**: Function key `{name, arity}` -> list of reachable Erlang MFAs

  ## Example

      iex> deps = elixir_stdlib_erlang_deps()
      iex> deps["Core"][Kernel][{:hd, 1}]
      [{:erlang, :hd, 1}]
  """
  @spec elixir_stdlib_erlang_deps() :: %{String.t() => %{module => %{{fun, arity} => [mfa]}}}
  def elixir_stdlib_erlang_deps do
    graph =
      Compiler.build_call_graph()
      |> CallGraph.remove_manually_ported_mfas()
      |> CallGraph.get_graph()

    Enum.reduce(@elixir_stdlib_module_groups, %{}, fn {group, modules}, groups_acc ->
      group_map =
        Enum.reduce(modules, %{}, fn module, modules_acc ->
          module_map =
            Enum.reduce(module.__info__(:functions), %{}, fn {fun, arity}, funs_acc ->
              reachable_erlang_mfas = reachable_erlang_mfas(graph, {module, fun, arity})
              Map.put(funs_acc, {fun, arity}, reachable_erlang_mfas)
            end)

          Map.put(modules_acc, module, module_map)
        end)

      Map.put(groups_acc, group, group_map)
    end)
  end

  defp reachable_erlang_mfas(graph, mfa) do
    graph
    |> CallGraph.reachable_mfas([mfa])
    |> Enum.filter(fn {module, _fun, _arity} -> Reflection.erlang_module?(module) end)
  end
end
