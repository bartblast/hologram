defmodule Hologram.Compiler.CallGraph do
  alias Hologram.Commons.PLT
  alias Hologram.Commons.Reflection
  alias Hologram.Commons.SerializationUtils
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.IR

  defstruct pid: nil
  @type t :: %CallGraph{pid: pid}

  @type vertex :: module | {module, atom, integer}

  @doc """
  Adds an edge between two vertices in the call graph.
  """
  @spec add_edge(CallGraph.t(), vertex, vertex) :: CallGraph.t()
  def add_edge(call_graph, from_vertex, to_vertex) do
    func = &Graph.add_edge(&1, from_vertex, to_vertex)
    tap(call_graph, &Agent.update(&1.pid, func))
  end

  @doc """
  Adds multiple edges to the call graph.
  """
  @spec add_edges(CallGraph.t(), list(Graph.Edge.t())) :: CallGraph.t()
  def add_edges(call_graph, edges) do
    func = &Graph.add_edges(&1, edges)
    tap(call_graph, &Agent.update(&1.pid, func))
  end

  @doc """
  Adds the vertex to the call graph.
  """
  @spec add_vertex(CallGraph.t(), vertex) :: CallGraph.t()
  def add_vertex(call_graph, vertex) do
    func = &Graph.add_vertex(&1, vertex)
    tap(call_graph, &Agent.update(&1.pid, func))
  end

  @doc """
  Builds a call graph from IR.
  """
  @spec build(CallGraph.t(), IR.t(), vertex | nil) :: CallGraph.t()
  def build(call_graph, ir, from_vertex \\ nil)

  def build(call_graph, %IR.AtomType{value: value}, from_vertex) do
    if Reflection.elixir_module?(value) do
      call_graph
      |> tap(&add_edge(&1, from_vertex, value))
      |> tap(&maybe_add_protocol_call_graph_edges(&1, value))
      |> tap(&maybe_add_templatable_call_graph_edges(&1, value))
    else
      call_graph
    end
  end

  def build(
        call_graph,
        %IR.FunctionDefinition{name: name, arity: arity, clause: clause},
        from_vertex
      ) do
    build(call_graph, clause, {from_vertex, name, arity})
  end

  def build(
        call_graph,
        %IR.LocalFunctionCall{function: function, args: args},
        {module, _function, _arity} = from_vertex
      ) do
    to_vertex = {module, function, Enum.count(args)}

    call_graph
    |> tap(&add_edge(&1, from_vertex, to_vertex))
    |> tap(&build(&1, args, from_vertex))
  end

  def build(
        call_graph,
        %IR.ModuleDefinition{module: %IR.AtomType{value: module}, body: body},
        _from_vertex
      ) do
    call_graph
    |> tap(&maybe_add_templatable_call_graph_edges(&1, module))
    |> tap(&build(&1, body, module))
  end

  def build(
        call_graph,
        %IR.RemoteFunctionCall{
          module: %IR.AtomType{value: :erlang},
          function: :apply,
          args: [
            %IR.AtomType{value: module},
            %IR.AtomType{value: function},
            %IR.ListType{data: args}
          ]
        },
        from_vertex
      ) do
    to_vertex = {module, function, Enum.count(args)}

    call_graph
    |> tap(&add_edge(&1, from_vertex, to_vertex))
    |> tap(&build(&1, args, from_vertex))
  end

  def build(
        call_graph,
        %IR.RemoteFunctionCall{module: %IR.AtomType{value: module}} = ir,
        from_vertex
      ) do
    to_vertex = {module, ir.function, Enum.count(ir.args)}

    call_graph
    |> tap(&add_edge(&1, from_vertex, to_vertex))
    |> tap(&build(&1, ir.args, from_vertex))
  end

  def build(call_graph, list, from_vertex) when is_list(list) do
    Enum.each(list, &build(call_graph, &1, from_vertex))
    call_graph
  end

  def build(call_graph, map, from_vertex) when is_map(map) do
    map
    |> Map.to_list()
    |> Enum.each(fn {key, value} ->
      call_graph
      |> tap(&build(&1, key, from_vertex))
      |> tap(&build(&1, value, from_vertex))
    end)

    call_graph
  end

  def build(call_graph, tuple, from_vertex) when is_tuple(tuple) do
    tap(call_graph, fn call_graph ->
      tuple
      |> Tuple.to_list()
      |> Enum.each(&build(call_graph, &1, from_vertex))
    end)
  end

  def build(call_graph, _ir, _from_vertex), do: call_graph

  @doc """
  Returns a clone of the given call graph.
  """
  @spec clone(CallGraph.t()) :: CallGraph.t()
  def clone(call_graph) do
    call_graph
    |> get_graph()
    |> then(&put_graph(start(), &1))
  end

  @doc """
  Serializes the call graph and writes it to a file.
  """
  @spec dump(CallGraph.t(), String.t()) :: CallGraph.t()
  def dump(call_graph, path) do
    tap(call_graph, fn call_graph ->
      path
      |> Path.dirname()
      |> File.mkdir_p!()

      call_graph
      |> get_graph()
      |> SerializationUtils.serialize()
      |> tap(&File.write!(path, &1))
    end)
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
  Loads the graph from the given dump file.
  """
  @spec load(CallGraph.t(), String.t()) :: CallGraph.t()
  def load(call_graph, dump_path) do
    dump_path
    |> File.read!()
    |> SerializationUtils.deserialize(true)
    |> then(&put_graph(call_graph, &1))
  end

  @doc """
  Loads the graph from the given dump file if the file exists.
  """
  @spec maybe_load(CallGraph.t(), String.t()) :: CallGraph.t()
  def maybe_load(call_graph, dump_path) do
    if File.exists?(dump_path) do
      load(call_graph, dump_path)
    else
      call_graph
    end
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
  Given a diff of changes, updates the call graph
  by deleting the graph paths of modules that have been removed,
  rebuilding the graph paths of modules that have been updated,
  and adding the graph paths of modules that have been added.
  """
  @spec patch(CallGraph.t(), PLT.t(), map) :: CallGraph.t()
  def patch(call_graph, ir_plt, diff) do
    diff.removed_modules
    |> Task.async_stream(&remove_module_vertices(call_graph, &1))
    |> Stream.run()

    diff.updated_modules
    |> Task.async_stream(fn module ->
      inbound_remote_edges = inbound_remote_edges(call_graph, module)
      remove_module_vertices(call_graph, module)
      build_module(call_graph, ir_plt, module)
      add_edges(call_graph, inbound_remote_edges)
    end)
    |> Stream.run()

    diff.added_modules
    |> Task.async_stream(&build_module(call_graph, ir_plt, &1))
    |> Stream.run()

    call_graph
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
  Lists MFAs that are reachable from the given entry MFA or MFAs.
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
  def remove_vertex(call_graph, vertex) do
    func = &Graph.delete_vertex(&1, vertex)
    tap(call_graph, &Agent.update(&1.pid, func))
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
    fn -> Graph.new() end
    |> Agent.start_link()
    |> then(fn {:ok, pid} -> %CallGraph{pid: pid} end)
  end

  @doc """
  Returns graph vertices.
  """
  @spec vertices(CallGraph.t()) :: list(vertex)
  def vertices(%{pid: pid}) do
    Agent.get(pid, &Graph.vertices/1)
  end

  defp add_component_call_graph_edges(call_graph, module) do
    call_graph
    |> tap(&add_edge(&1, module, {module, :action, 3}))
    |> tap(&add_edge(&1, module, {module, :init, 1}))
    |> tap(&add_edge(&1, module, {module, :template, 0}))
  end

  defp add_page_call_graph_edges(call_graph, module) do
    add_edge(call_graph, module, {module, :__route__, 0})
  end

  defp add_protocol_call_graph_edges(call_graph, module) do
    for impl <- Reflection.list_protocol_implementations(module),
        {name, arity} <- module.__protocol__(:functions) do
      add_edge(call_graph, {module, name, arity}, {impl, name, arity})
    end
  end

  defp build_module(call_graph, ir_plt, module) do
    ir_plt
    |> PLT.get!(module)
    |> then(&build(call_graph, &1))
  end

  defp inbound_edges(%{pid: pid}, vertex) do
    Agent.get(pid, &Graph.in_edges(&1, vertex))
  end

  defp maybe_add_protocol_call_graph_edges(call_graph, module) do
    if Reflection.protocol?(module) do
      add_protocol_call_graph_edges(call_graph, module)
    end
  end

  defp maybe_add_templatable_call_graph_edges(call_graph, module) do
    Reflection.page?(module) && add_page_call_graph_edges(call_graph, module)
    Reflection.component?(module) && add_component_call_graph_edges(call_graph, module)
  end

  defp remove_module_vertices(call_graph, module) do
    call_graph
    |> module_vertices(module)
    |> Enum.each(&remove_vertex(call_graph, &1))
  end
end
