defmodule Hologram.Compiler.ReflectionGate do
  @moduledoc false

  # Decides which reflection functions (see Hologram.Compiler.ReflectionSites) a page's client code
  # can call. A call on a named module gives the call graph an edge to the function it calls, so a
  # reflection function the graph cannot see runs on the client only through a call on a module the
  # code does not name: the page's own, or the runtime's, which every page loads.

  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Digraph
  alias Hologram.Compiler.ReflectionSites

  # What the gate is given besides the page's reach: the reflection functions the runtime's own
  # calls open.
  @type t :: %{runtime: %{open: MapSet.t({atom, arity})}}

  @doc """
  Returns the reflection functions, as `{name, arity}` tuples, that the given gate opens for a page
  whose client code reaches the given vertices: those a reflection site among the vertices calls,
  and those the runtime opens. With no gate, every reflection function is open, which is what the
  compiler did before it had one.
  """
  @spec open_functions(Digraph.t(), Enumerable.t(CallGraph.vertex()), t | nil) ::
          MapSet.t({atom, arity})
  def open_functions(graph, reached_vertices, gate)

  def open_functions(_graph, _reached_vertices, nil), do: MapSet.new(ReflectionSites.functions())

  def open_functions(_graph, reached_vertices, gate) do
    for {:reflection_site, _mfa, name, arity, _kind} <- reached_vertices,
        into: gate.runtime.open do
      {name, arity}
    end
  end
end
