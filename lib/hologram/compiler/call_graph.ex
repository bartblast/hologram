defmodule Hologram.Compiler.CallGraph do
  alias Hologram.Commons.SerializationUtils
  alias Hologram.Compiler.CallGraph

  defstruct pid: nil
  @type t :: %CallGraph{pid: pid}

  @type vertex :: module | {module, atom, integer}

  @doc """
  Adds an edge between two vertices in the call graph.
  """
  @spec add_edge(CallGraph.t(), vertex, vertex) :: CallGraph.t()
  def add_edge(%{pid: pid} = call_graph, from_vertex, to_vertex) do
    Agent.update(pid, &Graph.add_edge(&1, from_vertex, to_vertex))
    call_graph
  end

  @doc """
  Adds multiple edges to the call graph.
  """
  @spec add_edges(CallGraph.t(), list(Graph.Edge.t())) :: CallGraph.t()
  def add_edges(%{pid: pid} = call_graph, edges) do
    Agent.update(pid, &Graph.add_edges(&1, edges))
    call_graph
  end

  @doc """
  Adds the vertex to the call graph.
  """
  @spec add_vertex(CallGraph.t(), vertex) :: CallGraph.t()
  def add_vertex(%{pid: pid} = call_graph, vertex) do
    Agent.update(pid, &Graph.add_vertex(&1, vertex))
    call_graph
  end

  @doc """
  Returns a clone of the given call graph.
  """
  @spec clone(CallGraph.t()) :: CallGraph.t()
  def clone(call_graph) do
    graph = get_graph(call_graph)
    put_graph(start(), graph)
  end

  @doc """
  Serializes the call graph and writes it to a file.
  """
  @spec dump(CallGraph.t(), String.t()) :: CallGraph.t()
  def dump(call_graph, path) do
    data =
      call_graph
      |> get_graph()
      |> SerializationUtils.serialize()

    File.write!(path, data)

    call_graph
  end

  @doc """
  Returns graph edges.
  """
  @spec edges(CallGraph.t()) :: list(Graph.Edge.t())
  def edges(%{pid: pid}) do
    Agent.get(pid, &Graph.edges/1)
  end

  @doc """
  Returns the underlying libgraph %Graph{} struct containing vertices and edges data.
  """
  @spec get_graph(CallGraph.t()) :: Graph.t()
  def get_graph(%{pid: pid}) do
    Agent.get(pid, & &1)
  end

  @doc """
  Checks if an edge exists between two given vertices in the call graph.
  """
  @spec has_edge?(CallGraph.t(), vertex, vertex) :: boolean
  def has_edge?(call_graph, from_vertex, to_vertex) do
    call_graph
    |> get_graph()
    |> Graph.edge(from_vertex, to_vertex)
    |> is_struct(Graph.Edge)
  end

  @doc """
  Checks if the given vertex exists in the call graph.
  """
  @spec has_vertex?(CallGraph.t(), vertex) :: boolean
  def has_vertex?(%{pid: pid}, vertex) do
    Agent.get(pid, &Graph.has_vertex?(&1, vertex))
  end

  @doc """
  Returns the edges in which the second vertex is either the given module or a function from the given module,
  and the first vertex is a function from a different module.
  """
  @spec inbound_remote_edges(CallGraph.t(), module) :: list(Graph.Edge.t())
  def inbound_remote_edges(call_graph, to_module) do
    call_graph
    |> module_vertices(to_module)
    |> Enum.reduce([], fn vertex, acc ->
      call_graph
      |> inbound_edges(vertex)
      |> Enum.filter(fn
        %{v1: {from_module, _fun, _arity}} when from_module != to_module -> true
        _fallback -> false
      end)
      |> Enum.concat(acc)
    end)
  end

  @doc """
  Returns the list of vertices that are MFAs belonging to the given module.
  """
  @spec module_vertices(CallGraph.t(), module) :: list(vertex)
  def module_vertices(call_graph, module) do
    call_graph
    |> vertices()
    |> Enum.filter(fn
      ^module -> true
      {^module, _fun, _arity} -> true
      _fallback -> false
    end)
  end

  @doc """
  Replace the state of underlying Agent process with the given graph.
  """
  @spec put_graph(CallGraph.t(), Graph.t()) :: CallGraph.t()
  def put_graph(%{pid: pid} = call_graph, graph) do
    Agent.update(pid, fn _state -> graph end)
    call_graph
  end

  @doc """
  Lists vertices that are reachable from the given vertex or vertices.
  """
  @spec reachable(CallGraph.t(), vertex | list(vertex)) :: list(vertex)
  def reachable(call_graph, vertex_or_vertices)

  def reachable(%{pid: pid}, vertices) when is_list(vertices) do
    Agent.get(pid, &Graph.reachable(&1, vertices))
  end

  def reachable(call_graph, vertex) do
    reachable(call_graph, [vertex])
  end

  @doc """
  Lists MFAs ({module, function, arity} tuples) that are reachable from the given entry MFA or MFAs.
  """
  @spec reachable_mfas(CallGraph.t(), mfa | list(mfa)) :: list(mfa)
  def reachable_mfas(call_graph, entry_mfa_or_mfas) do
    call_graph
    |> reachable(entry_mfa_or_mfas)
    |> Enum.filter(&is_tuple/1)
  end

  @doc """
  Removes the vertex from the call graph.
  """
  @spec remove_vertex(CallGraph.t(), vertex) :: CallGraph.t()
  def remove_vertex(%{pid: pid} = call_graph, vertex) do
    Agent.update(pid, &Graph.delete_vertex(&1, vertex))
    call_graph
  end

  @doc """
  Returns sorted graph edges.
  """
  @spec sorted_edges(CallGraph.t()) :: list(Graph.Edge.t())
  def sorted_edges(call_graph) do
    call_graph
    |> edges()
    |> Enum.sort()
  end

  @doc """
  Returns sorted graph vertices.
  """
  @spec sorted_vertices(CallGraph.t()) :: list(vertex)
  def sorted_vertices(call_graph) do
    call_graph
    |> vertices()
    |> Enum.sort()
  end

  @doc """
  Starts a new CallGraph agent with an initial empty graph.
  """
  @spec start() :: CallGraph.t()
  def start do
    {:ok, pid} = Agent.start_link(fn -> Graph.new() end)
    %CallGraph{pid: pid}
  end

  @doc """
  Returns graph vertices.
  """
  @spec vertices(CallGraph.t()) :: list(vertex)
  def vertices(%{pid: pid}) do
    Agent.get(pid, &Graph.vertices/1)
  end

  defp inbound_edges(%{pid: pid}, vertex) do
    Agent.get(pid, &Graph.in_edges(&1, vertex))
  end

  ### OVERHAUL

  # use Agent

  # alias Hologram.Commons.PLT
  # alias Hologram.Compiler.IR
  # alias Hologram.Compiler.Reflection

  # @doc """
  # Builds a call graph from IR.

  # ## Examples

  #     iex> call_graph = %CallGraph{name: :my_call_graph, pid: #PID<0.259.0>}
  #     iex> ir = %IR.LocalFunctionCall{function: :my_fun, args: [%IR.IntegerType{value: 123}]}
  #     iex> build(call_graph, ir, MyModule)
  #     %CallGraph{name: :my_call_graph, pid: #PID<0.259.0>}
  # """
  # @spec build(CallGraph.t(), IR.t(), vertex | nil) :: CallGraph.t()
  # def build(call_graph, ir, from_vertex \\ nil)

  # def build(call_graph, %IR.AtomType{value: value}, from_vertex) do
  #   if Reflection.module?(value) do
  #     add_edge(call_graph, from_vertex, value)
  #     maybe_add_templatable_call_graph_edges(call_graph, value)
  #   end

  #   call_graph
  # end

  # def build(
  #       call_graph,
  #       %IR.FunctionDefinition{name: name, arity: arity, clause: clause},
  #       from_vertex
  #     ) do
  #   new_from_vertex = {from_vertex, name, arity}
  #   build(call_graph, clause, new_from_vertex)
  # end

  # def build(
  #       call_graph,
  #       %IR.LocalFunctionCall{function: function, args: args},
  #       {module, _function, _arity} = from_vertex
  #     ) do
  #   to_vertex = {module, function, Enum.count(args)}
  #   add_edge(call_graph, from_vertex, to_vertex)

  #   build(call_graph, args, from_vertex)
  # end

  # def build(
  #       call_graph,
  #       %IR.ModuleDefinition{module: %IR.AtomType{value: module}, body: body},
  #       _from_vertex
  #     ) do
  #   maybe_add_templatable_call_graph_edges(call_graph, module)
  #   build(call_graph, body, module)
  # end

  # def build(
  #       call_graph,
  #       %IR.RemoteFunctionCall{
  #         module: %IR.AtomType{value: :erlang},
  #         function: :apply,
  #         args: [
  #           %IR.AtomType{value: module},
  #           %IR.AtomType{value: function},
  #           %IR.ListType{data: args}
  #         ]
  #       },
  #       from_vertex
  #     ) do
  #   to_vertex = {module, function, Enum.count(args)}
  #   add_edge(call_graph, from_vertex, to_vertex)

  #   build(call_graph, args, from_vertex)
  # end

  # def build(
  #       call_graph,
  #       %IR.RemoteFunctionCall{
  #         module: %IR.AtomType{value: module},
  #         function: function,
  #         args: args
  #       },
  #       from_vertex
  #     ) do
  #   to_vertex = {module, function, Enum.count(args)}
  #   add_edge(call_graph, from_vertex, to_vertex)

  #   build(call_graph, args, from_vertex)
  # end

  # def build(call_graph, list, from_vertex) when is_list(list) do
  #   Enum.each(list, &build(call_graph, &1, from_vertex))
  #   call_graph
  # end

  # def build(call_graph, map, from_vertex) when is_map(map) do
  #   map
  #   |> Map.to_list()
  #   |> Enum.each(fn {key, value} ->
  #     build(call_graph, key, from_vertex)
  #     build(call_graph, value, from_vertex)
  #   end)

  #   call_graph
  # end

  # def build(call_graph, tuple, from_vertex) when is_tuple(tuple) do
  #   tuple
  #   |> Tuple.to_list()
  #   |> Enum.each(&build(call_graph, &1, from_vertex))

  #   call_graph
  # end

  # def build(call_graph, _ir, _from_vertex), do: call_graph

  # @doc """
  # Given a diff of changes, updates the call graph
  # by deleting the graph paths of modules that have been removed,
  # rebuilding the graph paths of modules that have been updated,
  # and adding the graph paths of modules that have been added.

  # ## Examples

  #     iex> call_graph = %CallGraph{name: :my_call_graph, pid: #PID<0.259.0>}
  #     iex> ir_plt = %PLT{name: :my_ir_plt, pid: #PID<0.253.0>}
  #     iex> diff = %{
  #     ...>   added_modules: [Module1, Module2],
  #     ...>   removed_modules: [Module5, Module6],
  #     ...>   updated_modules: [Module3, Module4]
  #     ...> }
  #     iex> patch(call_graph, ir_plt, diff)
  #     %CallGraph{name: :my_call_graph, pid: #PID<0.259.0>}
  # """
  # @spec patch(CallGraph.t(), PLT.t(), map) :: CallGraph.t()
  # def patch(call_graph, ir_plt, diff) do
  #   diff.removed_modules
  #   |> Task.async_stream(&remove_module_vertices(call_graph, &1))
  #   |> Stream.run()

  #   diff.updated_modules
  #   |> Task.async_stream(fn module ->
  #     inbound_remote_edges = inbound_remote_edges(call_graph, module)
  #     remove_module_vertices(call_graph, module)
  #     build_module(call_graph, ir_plt, module)
  #     add_edges(call_graph, inbound_remote_edges)
  #   end)
  #   |> Stream.run()

  #   diff.added_modules
  #   |> Task.async_stream(&build_module(call_graph, ir_plt, &1))
  #   |> Stream.run()

  #   call_graph
  # end

  # defp add_component_call_graph_edges(call_graph, module) do
  #   add_edge(call_graph, module, {module, :action, 3})
  #   add_edge(call_graph, module, {module, :init, 1})
  #   add_edge(call_graph, module, {module, :template, 0})
  # end

  # defp add_page_call_graph_edges(call_graph, module) do
  #   add_edge(call_graph, module, {module, :__hologram_route__, 0})
  # end

  # defp build_module(call_graph, ir_plt, module) do
  #   module_def = PLT.get!(ir_plt, module)
  #   build(call_graph, module_def)
  # end

  # defp load_graph_from_file(%{dump_path: dump_path} = call_graph) do
  #   graph =
  #     dump_path
  #     |> File.read!()
  #     |> SerializationUtils.deserialize()

  #   put_graph(call_graph, graph)
  # end

  # defp maybe_add_templatable_call_graph_edges(call_graph, module) do
  #   if Reflection.page?(module) do
  #     add_page_call_graph_edges(call_graph, module)
  #   end

  #   if Reflection.component?(module) do
  #     add_component_call_graph_edges(call_graph, module)
  #   end
  # end

  # defp put_graph(call_graph, graph) do
  #   Agent.update(call_graph.name, fn _state -> graph end)
  #   call_graph
  # end

  # defp remove_module_vertices(call_graph, module) do
  #   call_graph
  #   |> module_vertices(module)
  #   |> Enum.each(&remove_vertex(call_graph, &1))
  # end
end
