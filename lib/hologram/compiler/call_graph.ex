defmodule Hologram.Compiler.CallGraph do
  use Agent

  alias Hologram.Commons.PLT
  alias Hologram.Commons.SerializationUtils
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.IR
  alias Hologram.Compiler.Reflection

  defstruct pid: nil, name: nil, dump_path: nil
  @type t :: %CallGraph{pid: pid, name: atom, dump_path: String.t() | nil}

  @type vertex :: module | {module, atom, integer}

  @doc """
  Adds an edge between two vertices in the call graph.

  ## Examples

      iex> call_graph = %CallGraph{name: :my_call_graph, pid: #PID<0.259.0>}
      iex> add_adge(call_graph, :vertex_1, :vertex_2)
      %CallGraph{name: :my_call_graph, pid: #PID<0.259.0>}
  """
  @spec add_edge(CallGraph.t(), vertex, vertex) :: CallGraph.t()
  def add_edge(call_graph, from_vertex, to_vertex) do
    Agent.update(call_graph.name, &Graph.add_edge(&1, from_vertex, to_vertex))
    call_graph
  end

  @doc """
  Adds multiple edges to the call graph.

  ## Examples

      iex> call_graph = %CallGraph{name: :my_call_graph, pid: #PID<0.259.0>}
      iex> edges = [Graph.Edge.new(:a, :b), Graph.Edge.new(:c, :d)]
      iex> add_adges(call_graph, edges)
      %CallGraph{name: :my_call_graph, pid: #PID<0.259.0>}
  """
  @spec add_edges(CallGraph.t(), list(Graph.Edge.t())) :: CallGraph.t()
  def add_edges(call_graph, edges) do
    Agent.update(call_graph.name, &Graph.add_edges(&1, edges))
    call_graph
  end

  @doc """
  Adds the vertex to the call graph.

  ## Examples

      iex> call_graph = %CallGraph{name: :my_call_graph, pid: #PID<0.259.0>}
      iex> add_vertex(call_graph, :vertex_3)
      %CallGraph{name: :my_call_graph, pid: #PID<0.259.0>}
  """
  @spec add_vertex(CallGraph.t(), vertex) :: CallGraph.t()
  def add_vertex(call_graph, vertex) do
    Agent.update(call_graph.name, &Graph.add_vertex(&1, vertex))
    call_graph
  end

  @doc """
  Builds a call graph from IR.

  ## Examples

      iex> call_graph = %CallGraph{name: :my_call_graph, pid: #PID<0.259.0>}
      iex> ir = %IR.LocalFunctionCall{function: :my_fun, args: [%IR.IntegerType{value: 123}]}
      iex> build(call_graph, ir, MyModule)
      %CallGraph{name: :my_call_graph, pid: #PID<0.259.0>}
  """
  @spec build(CallGraph.t(), IR.t(), vertex | nil) :: CallGraph.t()
  def build(call_graph, ir, from_vertex \\ nil)

  def build(call_graph, %IR.AtomType{value: value}, from_vertex) do
    if Reflection.alias?(value) do
      add_edge(call_graph, from_vertex, value)

      if Reflection.page?(value) do
        add_page_call_graph_edges(call_graph, value)
      end

      if Reflection.component?(value) do
        add_component_call_graph_edges(call_graph, value)
      end
    end

    call_graph
  end

  def build(call_graph, %IR.FunctionDefinition{} = ir, from_vertex) do
    new_from_vertex = {from_vertex, ir.name, ir.arity}
    build(call_graph, ir.clause, new_from_vertex)
  end

  def build(call_graph, %IR.LocalFunctionCall{} = ir, {module, _function, _arity} = from_vertex) do
    to_vertex = {module, ir.function, Enum.count(ir.args)}
    add_edge(call_graph, from_vertex, to_vertex)

    build(call_graph, ir.args, from_vertex)
  end

  def build(call_graph, %IR.ModuleDefinition{module: module, body: body}, _from_vertex) do
    build(call_graph, body, module.value)
  end

  def build(call_graph, %IR.RemoteFunctionCall{} = ir, from_vertex) do
    to_vertex = {ir.module.value, ir.function, Enum.count(ir.args)}
    add_edge(call_graph, from_vertex, to_vertex)

    build(call_graph, ir.args, from_vertex)
  end

  def build(call_graph, list, from_vertex) when is_list(list) do
    Enum.each(list, &build(call_graph, &1, from_vertex))
    call_graph
  end

  def build(call_graph, map, from_vertex) when is_map(map) do
    map
    |> Map.to_list()
    |> Enum.each(fn {key, value} ->
      build(call_graph, key, from_vertex)
      build(call_graph, value, from_vertex)
    end)

    call_graph
  end

  def build(call_graph, tuple, from_vertex) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.each(&build(call_graph, &1, from_vertex))

    call_graph
  end

  def build(call_graph, _ir, _from_vertex), do: call_graph

  @doc """
  Clones the call graph and uses a new name for it.

  ## Examples

      iex> clone(%CallGraph{name: :my_call_graph}, name: :my_call_graph_clone)
      %CallGraph{pid: #PID<0.259.0>, name: :my_call_graph_clone}
  """
  @spec clone(CallGraph.t(), keyword) :: CallGraph.t()
  def clone(old_call_graph, opts) do
    new_call_graph = start(opts)
    Agent.update(new_call_graph.name, fn _state -> graph(old_call_graph) end)
    new_call_graph
  end

  @doc """
  Serializes the graph and writes it to a file.

  ## Examples

      iex> dump(%CallGraph{name: :my_call_graph, dump_path: "/my_dump_path"})
      :ok
  """
  @spec dump(CallGraph.t()) :: :ok
  def dump(%CallGraph{dump_path: dump_path} = call_graph) do
    data =
      call_graph
      |> graph()
      |> SerializationUtils.serialize()

    File.write!(dump_path, data)
  end

  @doc """
  Returns graph edges.

  ## Examples

      iex> edges(%CallGraph{name: :my_call_graph})
      [
        %Graph.Edge{
          v1: {Module2, :my_fun_6, 3},
          v2: Module5,
          weight: 1,
          label: nil
        },
        %Graph.Edge{
          v1: {Module3, :my_fun_8, 1},
          v2: {Module5, :my_fun_1, 4},
          weight: 1,
          label: nil
        }
      ]
  """
  @spec edges(CallGraph.t()) :: list(Graph.Edge.t())
  def edges(call_graph) do
    Agent.get(call_graph.name, &Graph.edges/1)
  end

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
  @spec has_edge?(CallGraph.t(), vertex, vertex) :: boolean
  def has_edge?(call_graph, from_vertex, to_vertex) do
    getter = fn graph ->
      Graph.edge(graph, from_vertex, to_vertex) != nil
    end

    Agent.get(call_graph.name, getter)
  end

  @doc """
  Checks if the given vertex exists in the call graph.

  ## Examples

      iex> call_graph = %CallGraph{name: :my_call_graph, pid: #PID<0.259.0>}
      iex> has_vertex?(call_graph, :vertex_3)
      true
  """
  @spec has_vertex?(CallGraph.t(), vertex) :: boolean
  def has_vertex?(call_graph, vertex) do
    Agent.get(call_graph.name, &Graph.has_vertex?(&1, vertex))
  end

  @doc """
  Returns the edges in which the second vertex is either the given module or a function from the given module,
  and the first vertex is a function from a different module.

  ## Examples

      iex> call_graph = %CallGraph{name: :my_call_graph, pid: #PID<0.259.0>}
      iex> inbound_remote_edges(call_graph, Module5)
      [
        %Graph.Edge{
          v1: {Module2, :my_fun_6, 3},
          v2: Module5,
          weight: 1,
          label: nil
        },
        %Graph.Edge{
          v1: {Module3, :my_fun_8, 1},
          v2: {Module5, :my_fun_1, 4},
          weight: 1,
          label: nil
        }
      ]
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
  Returns the list of vertices which belong to the given module.

  ## Examples

      iex> call_graph = %CallGraph{name: :my_call_graph, pid: #PID<0.259.0>}
      iex> vertices(call_graph, Module5)
      [Module5, {Module5, :my_fun_1, 3}, {Module5, :my_fun_2, 1}]
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
  Given a diff of changes, updates the call graph
  by deleting the graph paths of modules that have been removed,
  rebuilding the graph paths of modules that have been updated,
  and adding the graph paths of modules that have been added.

  ## Examples

      iex> call_graph = %CallGraph{name: :my_call_graph, pid: #PID<0.259.0>}
      iex> ir_plt = %PLT{name: :my_ir_plt, pid: #PID<0.253.0>}
      iex> diff = %{
      ...>   added_modules: [Module1, Module2],
      ...>   removed_modules: [Module5, Module6],
      ...>   updated_modules: [Module3, Module4]
      ...> }
      iex> patch(call_graph, ir_plt, diff)
      %CallGraph{name: :my_call_graph, pid: #PID<0.259.0>}
  """
  @spec patch(CallGraph.t(), PLT.t(), map) :: CallGraph.t()
  def patch(call_graph, ir_plt, diff) do
    Enum.each(diff.removed_modules, &remove_module_vertices(call_graph, &1))

    Enum.each(diff.updated_modules, fn module ->
      inbound_remote_edges = inbound_remote_edges(call_graph, module)
      remove_module_vertices(call_graph, module)
      build_module(call_graph, ir_plt, module)
      add_edges(call_graph, inbound_remote_edges)
    end)

    Enum.each(diff.added_modules, &build_module(call_graph, ir_plt, &1))

    call_graph
  end

  @doc """
  Determines vertices which are reachable from the given vertex.

  ## Examples

      iex> reachable(%CallGraph{name: :my_call_graph}, :vertex_3)
      [:vertex_12, :vertex_5, :vertex_9, :vertex_3]
  """
  @spec reachable(CallGraph.t(), vertex) :: list(vertex)
  def reachable(call_graph, vertex) do
    Agent.get(call_graph.name, &Graph.reachable(&1, [vertex]))
  end

  @doc """
  Removes the vertex from the call graph.

  ## Examples

      iex> call_graph = %CallGraph{name: :my_call_graph, pid: #PID<0.259.0>}
      iex> remove_vertex(call_graph, :vertex_3)
      %CallGraph{name: :my_call_graph, pid: #PID<0.259.0>}
  """
  @spec remove_vertex(CallGraph.t(), vertex) :: CallGraph.t()
  def remove_vertex(call_graph, vertex) do
    Agent.update(call_graph.name, &Graph.delete_vertex(&1, vertex))
    call_graph
  end

  @doc """
  Starts a new CallGraph agent with an initial empty graph
  or loads the graph from the dump file if it exists.

  ## Examples

      iex> start(name: :my_call_graph, dump_path: "/my_dump_path")
      %CallGraph{pid: #PID<0.259.0>, name: :my_call_graph, dump_path: "/my_dump_path"}
  """
  @spec start(keyword) :: CallGraph.t()
  def start(opts) do
    {:ok, pid} = Agent.start_link(fn -> Graph.new() end, name: opts[:name])

    call_graph = %CallGraph{pid: pid, name: opts[:name], dump_path: opts[:dump_path]}

    if opts[:dump_path] && File.exists?(opts[:dump_path]) do
      load_graph_from_file(call_graph)
    end

    call_graph
  end

  @doc """
  Returns graph vertices.

  ## Examples

      iex> vertices(%CallGraph{name: :my_call_graph})
      [:vertex_5, :vertex_1, :vertex_3]
  """
  @spec vertices(CallGraph.t()) :: list(vertex)
  def vertices(call_graph) do
    Agent.get(call_graph.name, &Graph.vertices/1)
  end

  defp add_component_call_graph_edges(call_graph, module) do
    add_edge(call_graph, module, {module, :action, 3})
    add_edge(call_graph, module, {module, :init, 1})
    add_edge(call_graph, module, {module, :template, 0})
  end

  defp build_module(call_graph, ir_plt, module) do
    module_def = PLT.get!(ir_plt, module)
    build(call_graph, module_def)
  end

  defp add_page_call_graph_edges(call_graph, module) do
    add_edge(call_graph, module, {module, :__hologram_layout_module__, 0})
    add_edge(call_graph, module, {module, :__hologram_route__, 0})
  end

  defp inbound_edges(call_graph, vertex) do
    Agent.get(call_graph.name, &Graph.in_edges(&1, vertex))
  end

  defp load_graph_from_file(%{dump_path: dump_path} = call_graph) do
    graph =
      dump_path
      |> File.read!()
      |> SerializationUtils.deserialize()

    put_graph(call_graph, graph)
  end

  defp put_graph(call_graph, graph) do
    Agent.update(call_graph.name, fn _state -> graph end)
    call_graph
  end

  defp remove_module_vertices(call_graph, module) do
    call_graph
    |> module_vertices(module)
    |> Enum.each(&remove_vertex(call_graph, &1))
  end
end
