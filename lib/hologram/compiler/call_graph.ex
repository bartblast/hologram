# TODO: remove comments

defmodule Hologram.Compiler.CallGraph do
  use Agent

  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.IR
  alias Hologram.Compiler.Reflection

  defstruct pid: nil, name: nil
  @type t :: %CallGraph{pid: pid, name: atom}

  @doc """
  Adds an edge between two vertices in the call graph.

  ## Examples

      iex> call_graph = %CallGraph{name: :my_call_graph, pid: #PID<0.259.0>}
      iex> add_adge(call_graph, :vertex_1, :vertex_2)
      :ok
  """
  @spec add_edge(CallGraph.t(), any, any) :: :ok
  def add_edge(call_graph, from_vertex, to_vertex) do
    Agent.update(call_graph.name, &Graph.add_edge(&1, from_vertex, to_vertex))
    :ok
  end

  @doc """
  Adds a vertex to the call graph.

  ## Examples

      iex> call_graph = %CallGraph{name: :my_call_graph, pid: #PID<0.259.0>}
      iex> add_vertex(call_graph, :vertex_3)
      :ok
  """
  @spec add_vertex(CallGraph.t(), any) :: :ok
  def add_vertex(call_graph, vertex) do
    Agent.update(call_graph.name, &Graph.add_vertex(&1, vertex))
    :ok
  end

  @doc """
  Builds a call graph from IR.

  ## Examples

      iex> call_graph = %CallGraph{name: :my_call_graph, pid: #PID<0.259.0>}
      iex> ir = %IR.LocalFunctionCall{function: :my_fun, args: [%IR.IntegerType{value: 123}]}
      iex> build(call_graph, ir, MyModule)
  """
  @spec build(CallGraph.t(), IR.t(), module | {module, atom, integer} | nil) :: :ok
  def build(call_graph, ir, from_vertex \\ nil)

  def build(call_graph, %IR.AtomType{value: value}, from_vertex) do
    if Reflection.alias?(value) do
      add_edge(call_graph, from_vertex, value)

      if Reflection.page?(value) do
        add_page_call_graph_edges(call_graph, value)
      end

      if Reflection.layout?(value) do
        add_layout_call_graph_edges(call_graph, value)
      end

      if Reflection.component?(value) do
        add_component_call_graph_edges(call_graph, value)
      end
    end

    :ok
  end

  def build(call_graph, %IR.FunctionDefinition{} = ir, from_vertex) do
    new_from_vertex = {from_vertex, ir.name, ir.arity}
    add_vertex(call_graph, new_from_vertex)
    build(call_graph, ir.clause, new_from_vertex)
  end

  def build(call_graph, %IR.LocalFunctionCall{} = ir, {module, _function, _arity} = from_vertex) do
    to_vertex = {module, ir.function, Enum.count(ir.args)}
    add_edge(call_graph, from_vertex, to_vertex)

    build(call_graph, ir.args, from_vertex)
  end

  def build(call_graph, %IR.ModuleDefinition{module: module, body: body}, _from_vertex) do
    add_vertex(call_graph, module)
    build(call_graph, body, module)
  end

  def build(call_graph, %IR.RemoteFunctionCall{} = ir, from_vertex) do
    to_vertex = {ir.module.value, ir.function, Enum.count(ir.args)}
    add_edge(call_graph, from_vertex, to_vertex)

    build(call_graph, ir.args, from_vertex)
  end

  def build(call_graph, list, from_vertex) when is_list(list) do
    Enum.each(list, &build(call_graph, &1, from_vertex))
    :ok
  end

  def build(call_graph, map, from_vertex) when is_map(map) do
    map
    |> Map.to_list()
    |> Enum.each(fn {key, value} ->
      build(call_graph, key, from_vertex)
      build(call_graph, value, from_vertex)
    end)

    :ok
  end

  def build(call_graph, tuple, from_vertex) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.each(&build(call_graph, &1, from_vertex))

    :ok
  end

  def build(_call_graph, _ir, _from_vertex), do: :ok

  @doc """
  Returns the underlying libgraph %Graph{} struct containing the information about vertices and edges.

  ## Examples

      iex> call_graph = CallGraph{name: :my_call_graph, pid: #PID<0.259.0>}
      iex> graph(call_graph)
      #Graph<type: directed, vertices: [], edges: []>
  """
  @spec graph(CallGraph.t()) :: Graph.t()
  def graph(call_graph) do
    Agent.get(call_graph.pid, & &1)
  end

  @doc """
  Checks if an edge exists between two given vertices in the call graph.

  ## Examples

      iex> call_graph = %CallGraph{name: :my_call_graph, pid: #PID<0.259.0>}
      iex> has_edge?(call_graph, :vertex_1, :vertex_2)
      true
  """
  @spec has_edge?(CallGraph.t(), any, any) :: boolean
  def has_edge?(call_graph, from_vertex, to_vertex) do
    getter = fn graph ->
      Graph.edge(graph, from_vertex, to_vertex) != nil
    end

    Agent.get(call_graph.name, getter)
  end

  # def edges(call_graph, vertex) do
  #   Agent.get(call_graph.name, &Graph.edges(&1, vertex))
  # end

  # def has_vertex?(call_graph, vertex) do
  #   Agent.get(call_graph, &Graph.has_vertex?(&1, vertex))
  # end

  # def num_edges(call_graph) do
  #   Agent.get(call_graph, &Graph.num_edges/1)
  # end

  # def num_vertices(call_graph) do
  #   Agent.get(call_graph, &Graph.num_vertices/1)
  # end

  # def reachable(call_graph, vertices) do
  #   Agent.get(call_graph, &Graph.reachable(&1, vertices))
  # end

  @doc """
  Starts a new CallGraph agent with an initial empty graph.

  ## Examples

      iex> start(name: :my_call_graph)
      %CallGraph{pid: #PID<0.259.0>, name: :my_call_graph}
  """
  @spec start(keyword) :: CallGraph.t()
  def start(opts) do
    {:ok, pid} = Agent.start_link(fn -> Graph.new() end, name: opts[:name])
    %CallGraph{pid: pid, name: opts[:name]}
  end

  # def stop(call_graph) do
  #   Agent.stop(call_graph.name)
  # end

  defp add_component_call_graph_edges(call_graph, module) do
    add_templatable_call_graph_edges(call_graph, module)
    add_edge(call_graph, module, {module, :init, 1})
  end

  defp add_layout_call_graph_edges(call_graph, module) do
    add_templatable_call_graph_edges(call_graph, module)
  end

  defp add_page_call_graph_edges(call_graph, module) do
    add_templatable_call_graph_edges(call_graph, module)

    add_edge(call_graph, module, {module, :__hologram_layout_module__, 0})
    add_edge(call_graph, module, {module, :__hologram_route__, 0})
  end

  defp add_templatable_call_graph_edges(call_graph, module) do
    add_edge(call_graph, module, {module, :action, 3})
    add_edge(call_graph, module, {module, :template, 0})
  end
end
