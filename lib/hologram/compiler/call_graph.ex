defmodule Hologram.Compiler.CallGraph do
  @moduledoc false

  alias Hologram.Commons.PLT
  alias Hologram.Commons.SerializationUtils
  alias Hologram.Commons.TaskUtils
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.IR
  alias Hologram.Reflection

  defstruct pid: nil
  @type t :: %CallGraph{pid: pid}

  @type vertex :: module | mfa

  @erlang_mfa_edges [
    {{:erlang, :"=<", 2}, {:erlang, :<, 2}},
    {{:erlang, :"=<", 2}, {:erlang, :==, 2}},
    {{:erlang, :>=, 2}, {:erlang, :==, 2}},
    {{:erlang, :>=, 2}, {:erlang, :>, 2}},
    {{:erlang, :atom_to_binary, 1}, {:erlang, :atom_to_binary, 2}},
    {{:erlang, :binary_to_atom, 1}, {:erlang, :binary_to_atom, 2}},
    {{:erlang, :binary_to_existing_atom, 1}, {:erlang, :binary_to_atom, 1}},
    {{:erlang, :binary_to_existing_atom, 2}, {:erlang, :binary_to_atom, 2}},
    {{:erlang, :error, 1}, {:erlang, :error, 2}},
    {{:erlang, :integer_to_binary, 1}, {:erlang, :integer_to_binary, 2}},
    {{:lists, :keymember, 3}, {:lists, :keyfind, 3}},
    {{:maps, :get, 2}, {:maps, :get, 3}},
    {{:maps, :update, 3}, {:maps, :is_key, 2}},
    {{:maps, :update, 3}, {:maps, :put, 3}},
    {{:unicode, :characters_to_binary, 1}, {:unicode, :characters_to_binary, 3}},
    {{:unicode, :characters_to_binary, 3}, {:lists, :flatten, 1}}
  ]

  # These functions are transpiled manually for at least one of the following reasons:
  # * the transpiled output is too large
  # * the transpiled output is deeply nested
  # * the function doesn't make sense on the client side
  # * the function must access the Hologram client runtime
  # * the function has only a client-side implementation
  @manually_ported_mfas [
    {Cldr.Locale, :language_data, 0},
    {Cldr.Validity.U, :encode_key, 2},
    {Code, :ensure_loaded, 1},
    {Hologram.JS, :exec, 1},
    {Hologram.Router.Helpers, :asset_path, 1},
    {IO, :inspect, 1},
    {IO, :inspect, 2},
    {IO, :inspect, 3},
    {Kernel, :inspect, 1},
    {Kernel, :inspect, 2},
    {String, :downcase, 1},
    {String, :downcase, 2},
    {String, :replace, 3},
    {String, :upcase, 1},
    {String, :upcase, 2}
  ]

  @mfas_used_by_all_pages_and_components [
    # Used by __params__/0 and __props__/0 functions injected into page and component modules respectively.
    {Enum, :reverse, 1},
    {Hologram.Component, :__struct__, 0},
    {Hologram.Component.Action, :__struct__, 0},
    {Hologram.Component.Command, :__struct__, 0},
    {Hologram.Router.Helpers, :page_path, 1},
    {Hologram.Router.Helpers, :page_path, 2}
  ]

  @mfas_used_by_client_runtime [
    asset_path_registry_class: [
      {:maps, :get, 3},
      {:maps, :put, 3}
    ],
    command_queue_class: [
      {:maps, :get, 2}
    ],
    component_registry_class: [
      {:maps, :get, 2},
      {:maps, :get, 3},
      {:maps, :is_key, 2}
    ],
    hologram_class: [
      {:maps, :get, 2},
      {:maps, :put, 3}
    ],
    interpreter_class: [
      {Enum, :into, 2},
      {Enum, :to_list, 1},
      {:erlang, :error, 1},
      {:erlang, :hd, 1},
      {:erlang, :tl, 1},
      {:lists, :keyfind, 3},
      {:lists, :sort, 1},
      {:maps, :get, 2},
      {:maps, :to_list, 1}
    ],
    manually_ported_code_module: [
      {:code, :ensure_loaded, 1}
    ],
    operation_class: [
      {:maps, :from_list, 1},
      {:maps, :get, 2},
      {:maps, :put, 3}
    ],
    renderer_class: [
      {Hologram.Component, :__struct__, 0},
      {String.Chars, :to_string, 1},
      {:erlang, :binary_to_atom, 1},
      {:lists, :flatten, 1},
      {:lists, :keyfind, 3},
      {:lists, :keymember, 3},
      {:maps, :from_list, 1},
      {:maps, :get, 2},
      {:maps, :is_key, 2},
      {:maps, :merge, 2}
    ],
    type_class: [
      {:maps, :get, 3},
      {:maps, :is_key, 2}
    ]
  ]

  @doc """
  Adds an edge between two vertices in the call graph.
  """
  @spec add_edge(CallGraph.t(), vertex, vertex) :: CallGraph.t()
  def add_edge(%{pid: pid} = call_graph, from_vertex, to_vertex) do
    Agent.update(pid, &Graph.add_edge(&1, from_vertex, to_vertex), :infinity)
    call_graph
  end

  @doc """
  Adds multiple edges to the call graph.
  """
  @spec add_edges(CallGraph.t(), list(Graph.Edge.t())) :: CallGraph.t()
  def add_edges(%{pid: pid} = call_graph, edges) do
    Agent.update(pid, &Graph.add_edges(&1, edges), :infinity)
    call_graph
  end

  @doc """
  Adds the vertex to the call graph.
  """
  @spec add_vertex(CallGraph.t(), vertex) :: CallGraph.t()
  def add_vertex(%{pid: pid} = call_graph, vertex) do
    Agent.update(pid, &Graph.add_vertex(&1, vertex), :infinity)
    call_graph
  end

  @doc """
  Builds a call graph from IR.
  """
  @spec build(CallGraph.t(), IR.t(), vertex | nil) :: CallGraph.t()
  def build(call_graph, ir, from_vertex \\ nil)

  def build(call_graph, %IR.AtomType{value: value}, from_vertex) do
    if Reflection.elixir_module?(value) do
      call_graph
      |> add_edge(from_vertex, value)
      |> maybe_add_protocol_call_graph_edges(value)
      |> maybe_add_struct_call_graph_edges(value)
      |> maybe_add_ecto_schema_call_graph_edges(value)
      |> maybe_add_templatable_call_graph_edges(value)
    end

    call_graph
  end

  def build(
        call_graph,
        %IR.FunctionDefinition{name: name, arity: arity, clause: clause},
        from_vertex
      ) do
    fun_def_vertex = {from_vertex, name, arity}

    call_graph
    |> add_vertex(fun_def_vertex)
    |> build(clause, fun_def_vertex)
  end

  def build(
        call_graph,
        %IR.LocalFunctionCall{function: function, args: args},
        {module, _function, _arity} = from_vertex
      ) do
    to_vertex = {module, function, Enum.count(args)}

    call_graph
    |> add_edge(from_vertex, to_vertex)
    |> build(args, from_vertex)
  end

  def build(
        call_graph,
        %IR.ModuleDefinition{module: %IR.AtomType{value: module}, body: body},
        _from_vertex
      ) do
    call_graph
    |> maybe_add_templatable_call_graph_edges(module)
    |> build(body, module)
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
    add_edge(call_graph, from_vertex, to_vertex)

    build(call_graph, args, from_vertex)
  end

  def build(
        call_graph,
        %IR.RemoteFunctionCall{
          module: %IR.AtomType{value: module},
          function: function,
          args: args
        },
        from_vertex
      ) do
    to_vertex = {module, function, Enum.count(args)}
    add_edge(call_graph, from_vertex, to_vertex)

    build(call_graph, args, from_vertex)
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
      |> build(key, from_vertex)
      |> build(value, from_vertex)
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
  Builds a call graph from a module definition IR located in the given IR PLT.
  """
  @spec build_for_module(CallGraph.t(), PLT.t(), module) :: CallGraph.t()
  def build_for_module(call_graph, ir_plt, module) do
    module_def = PLT.get!(ir_plt, module)
    build(call_graph, module_def)
  end

  @doc """
  Returns a clone of the given call graph.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/call_graph/clone_1/README.md
  """
  @spec clone(CallGraph.t()) :: CallGraph.t()
  def clone(call_graph) do
    graph = get_graph(call_graph)
    start(graph)
  end

  @doc """
  Serializes the call graph and writes it to a file.

  Benchmarks: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/call_graph/dump_2/README.md
  """
  @spec dump(CallGraph.t(), String.t()) :: CallGraph.t()
  def dump(call_graph, path) do
    data =
      call_graph
      |> get_graph()
      |> SerializationUtils.serialize()

    path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(path, data)

    call_graph
  end

  @doc """
  Returns graph edges.
  """
  @spec edges(CallGraph.t()) :: list(Graph.Edge.t())
  def edges(%{pid: pid}) do
    Agent.get(pid, &Graph.edges/1, :infinity)
  end

  @doc """
  Returns the underlying libgraph %Graph{} struct containing vertices and edges data.
  """
  @spec get_graph(CallGraph.t()) :: Graph.t()
  def get_graph(%{pid: pid}) do
    Agent.get(pid, & &1, :infinity)
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
    Agent.get(pid, &Graph.has_vertex?(&1, vertex), :infinity)
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
  Lists the entry MFAs {module, function, arity} for a given page module.

  This function returns a list of MFAs that are considered entry points for a page,
  including functions from both the page module and its associated layout module.

  ## Parameters

    * `page_module` - The module of the page for which to list entry MFAs.

  ## Returns

  A list of MFAs (tuples of {module, function, arity}) that serve as entry points
  for the given page module and its layout.
  """
  @spec list_page_entry_mfas(module()) :: list(mfa)
  def list_page_entry_mfas(page_module) do
    layout_module = page_module.__layout_module__()

    [
      {page_module, :__layout_module__, 0},
      {page_module, :__layout_props__, 0},
      {page_module, :__params__, 0},
      {page_module, :__route__, 0},
      {page_module, :action, 3},
      {page_module, :template, 0},
      {layout_module, :__props__, 0},
      {layout_module, :action, 3},
      {layout_module, :template, 0}
    ]
  end

  @doc """
  Returns the list of MFAs that are reachable by the given page.
  """
  @spec list_page_mfas(CallGraph.t(), module) :: list(mfa)
  def list_page_mfas(call_graph, page_module) do
    entry_mfas = list_page_entry_mfas(page_module)
    graph = get_graph(call_graph)

    graph
    |> sorted_reachable_mfas(entry_mfas)
    |> reject_hex_solver_mfas()
    |> add_reflection_mfas_reachable_from_server_inits(page_module, graph)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Lists entry runtime MFAs, which include MFAs used by the client runtime JS classes
  and client MFAs used by all pages and components.
  The returned MFAs are sorted.
  """
  @spec list_runtime_entry_mfas :: list(mfa)
  def list_runtime_entry_mfas do
    @mfas_used_by_client_runtime
    |> Enum.reduce(@mfas_used_by_all_pages_and_components, fn {_key, mfas}, acc ->
      mfas ++ acc
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Lists MFAs required by the runtime JS script.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/call_graph/list_runtime_mfas_1/README.md
  """
  @spec list_runtime_mfas(CallGraph.t()) :: list(mfa)
  def list_runtime_mfas(call_graph) do
    entry_mfas = list_runtime_entry_mfas()

    call_graph
    |> get_graph()
    |> add_edges_for_erlang_functions()
    |> sorted_reachable_mfas(entry_mfas)
    |> reject_hex_solver_mfas()
  end

  @doc """
  Loads the graph from the given dump file.
  """
  @spec load(CallGraph.t(), String.t()) :: CallGraph.t()
  def load(call_graph, dump_path) do
    graph =
      dump_path
      |> File.read!()
      |> SerializationUtils.deserialize(true)

    put_graph(call_graph, graph)
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

  Benchmarks: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/call_graph/patch_3/README.md
  """
  @spec patch(CallGraph.t(), PLT.t(), map) :: CallGraph.t()
  def patch(call_graph, ir_plt, diff) do
    remove_tasks =
      TaskUtils.async_many(diff.removed_modules, &remove_module_vertices(call_graph, &1))

    update_tasks =
      TaskUtils.async_many(diff.updated_modules, fn module ->
        inbound_remote_edges = inbound_remote_edges(call_graph, module)

        call_graph
        |> remove_module_vertices(module)
        |> build_for_module(ir_plt, module)
        |> add_edges(inbound_remote_edges)
      end)

    add_tasks =
      TaskUtils.async_many(diff.added_modules, &build_for_module(call_graph, ir_plt, &1))

    Task.await_many(remove_tasks, :infinity)
    Task.await_many(update_tasks, :infinity)
    Task.await_many(add_tasks, :infinity)

    call_graph
  end

  @doc """
  Replace the state of underlying Agent process with the given graph.
  """
  @spec put_graph(CallGraph.t(), Graph.t()) :: CallGraph.t()
  def put_graph(%{pid: pid} = call_graph, graph) do
    Agent.update(pid, fn _state -> graph end, :infinity)
    call_graph
  end

  @doc """
  Lists vertices that are reachable from the given graph vertex or vertices.
  """
  @spec reachable(Graph.t(), vertex | list(vertex)) :: list(vertex)
  def reachable(graph, vertex_or_vertices)

  def reachable(graph, vertices) when is_list(vertices) do
    graph
    |> Graph.reachable(vertices)
    |> Enum.reject(&(&1 == nil))
  end

  def reachable(graph, vertex) do
    reachable(graph, [vertex])
  end

  defp reject_hex_solver_mfas(mfas) do
    Enum.reject(mfas, fn {module, _function, _arity} ->
      module_str = to_string(module)

      String.starts_with?(module_str, "Elixir.Hex.Solver.") ||
        String.starts_with?(module_str, "Elixir.Inspect.Hex.Solver.") ||
        String.starts_with?(module_str, "Elixir.String.Chars.Hex.Solver.")
    end)
  end

  @doc """
  Removes call graph vertices for Elixir functions ported manually.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/call_graph/remove_manually_ported_mfas_1/README.md
  """
  @spec remove_manually_ported_mfas(CallGraph.t()) :: CallGraph.t()
  def remove_manually_ported_mfas(call_graph) do
    CallGraph.remove_vertices(call_graph, @manually_ported_mfas)
  end

  @doc """
  Removes call graph vertices and edges related to MFAs used by the runtime.

  remove_vertices/2 is very slow on large graphs -
  for a base case it would take over 7 seconds to remove runtime MFAs that way.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/call_graph/remove_runtime_mfas!_2/README.md
  """
  @spec remove_runtime_mfas!(CallGraph.t(), list(mfa)) :: CallGraph.t()
  def remove_runtime_mfas!(call_graph, runtime_mfas) do
    vertices = vertices(call_graph)
    edges = edges(call_graph)

    new_vertices = vertices -- runtime_mfas

    new_edges =
      Enum.reject(edges, fn %Graph.Edge{v1: from_vertex, v2: to_vertex} ->
        to_vertex in runtime_mfas or from_vertex in runtime_mfas
      end)

    new_graph =
      Graph.new()
      |> Graph.add_vertices(new_vertices)
      |> Graph.add_edges(new_edges)

    put_graph(call_graph, new_graph)
  end

  @doc """
  Removes the vertex from the call graph.
  """
  @spec remove_vertex(CallGraph.t(), vertex) :: CallGraph.t()
  def remove_vertex(%{pid: pid} = call_graph, vertex) do
    Agent.update(pid, &Graph.delete_vertex(&1, vertex), :infinity)
    call_graph
  end

  @doc """
  Removes the vertices from the call graph.

  Benchmarks: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/call_graph/remove_vertices_2/README.md
  """
  @spec remove_vertices(CallGraph.t(), list(vertex)) :: CallGraph.t()
  def remove_vertices(%{pid: pid} = call_graph, vertices) do
    Agent.update(pid, &Graph.delete_vertices(&1, vertices), :infinity)
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
  Lists MFAs that are reachable from the given call graph vertex or vertices.
  Unimplemented protocol implentations are excluded.
  The MFAs returned are sorted.
  """
  @spec sorted_reachable_mfas(Graph.t(), vertex | list(vertex)) :: list(mfa)
  def sorted_reachable_mfas(graph, vertex_or_vertices) do
    graph
    |> reachable(vertex_or_vertices)
    |> Enum.filter(fn
      # Some protocol implementations are referenced but not actually implemented, e.g. Collectable.Atom
      {module, _function, _arity} -> Reflection.module?(module)
      _module -> false
    end)
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
  Starts a new CallGraph agent with (optional) initial graph.
  """
  @spec start(Graph.t()) :: CallGraph.t()
  def start(graph \\ Graph.new()) do
    {:ok, pid} = Agent.start_link(fn -> graph end)
    %CallGraph{pid: pid}
  end

  @doc """
  Stops the CallGraph agent.
  """
  @spec stop(CallGraph.t()) :: :ok
  def stop(%CallGraph{pid: pid}) do
    Agent.stop(pid)
  end

  @doc """
  Returns graph vertices.
  """
  @spec vertices(CallGraph.t()) :: list(vertex)
  def vertices(%{pid: pid}) do
    Agent.get(pid, &Graph.vertices/1, :infinity)
  end

  # Add call graph edges for Erlang functions depending on other Erlang functions.
  # credo:disable-for-next-line Credo.Check.Refactor.ABCSize
  defp add_edges_for_erlang_functions(graph) do
    Graph.add_edges(graph, @erlang_mfa_edges)
  end

  # A component module can be passed as a prop to another component, allowing dynamic usage.
  # In such cases, when this scenario is identified, it becomes necessary
  # to include the entire component on the client side.
  # This is because we lack precise information about which specific component functions will be used.
  defp add_component_call_graph_edges(call_graph, module) do
    call_graph
    |> add_edge(module, {module, :__props__, 0})
    |> add_edge(module, {module, :action, 3})
    |> add_edge(module, {module, :init, 2})
    |> add_edge(module, {module, :template, 0})
  end

  # __props__/0 and __route__/0 functions are needed to build page link href (e.g. in Hologram.UI.Link component).
  defp add_page_call_graph_edges(call_graph, module) do
    call_graph
    |> add_edge(module, {module, :__params__, 0})
    |> add_edge(module, {module, :__route__, 0})
  end

  defp add_protocol_call_graph_edges(call_graph, module) do
    funs = module.__protocol__(:functions)
    impls = Reflection.list_protocol_implementations(module)

    Enum.each(impls, fn impl ->
      Enum.each(funs, fn {name, arity} ->
        call_graph
        |> add_edge({module, name, arity}, {impl, :__impl__, 1})
        |> add_edge({module, name, arity}, {impl, name, arity})
      end)
    end)
  end

  # Adds reflection MFAs, i.e.:
  # * __changeset__/0
  # * __schema__/1
  # * __schema__/2
  # * __struct__/0
  # * __struct__/1
  # that are reachable from server inits (init/3) of the components used by the page.
  defp add_reflection_mfas_reachable_from_server_inits(page_mfas, page_module, graph) do
    templatables = [page_module | extract_uniq_components(page_mfas)]

    added_mfas =
      Enum.reduce(templatables, [], fn templetable, acc ->
        acc ++ list_reflection_mfas_reachable_from_server_init(templetable, graph)
      end)

    page_mfas ++ added_mfas
  end

  defp extract_uniq_components(mfas) do
    mfas
    |> Enum.map(fn {module, _function, _arity} -> module end)
    |> Enum.uniq()
    |> Enum.filter(&Reflection.component?/1)
  end

  defp inbound_edges(%CallGraph{pid: pid}, vertex) do
    Agent.get(pid, &Graph.in_edges(&1, vertex), :infinity)
  end

  defp list_reflection_mfas_reachable_from_server_init(templetable, graph) do
    graph
    |> reachable({templetable, :init, 3})
    |> Enum.filter(fn mfa ->
      case mfa do
        {_module, :__changeset__, 0} -> true
        {_module, :__schema__, 1} -> true
        {_module, :__schema__, 2} -> true
        {_module, :__struct__, 0} -> true
        {_module, :__struct__, 1} -> true
        _falback -> false
      end
    end)
  end

  defp maybe_add_ecto_schema_call_graph_edges(call_graph, module) do
    if Reflection.ecto_schema?(module) do
      add_edges(call_graph, [
        Graph.Edge.new(module, {module, :__changeset__, 0}),
        Graph.Edge.new(module, {module, :__schema__, 1}),
        Graph.Edge.new(module, {module, :__schema__, 2})
      ])
    end

    call_graph
  end

  defp maybe_add_protocol_call_graph_edges(call_graph, module) do
    if Reflection.protocol?(module) do
      add_protocol_call_graph_edges(call_graph, module)
    end

    call_graph
  end

  defp maybe_add_struct_call_graph_edges(call_graph, module) do
    if Reflection.has_struct?(module) do
      add_edges(call_graph, [
        Graph.Edge.new(module, {module, :__struct__, 0}),
        Graph.Edge.new(module, {module, :__struct__, 1})
      ])
    end

    call_graph
  end

  defp maybe_add_templatable_call_graph_edges(call_graph, module) do
    if Reflection.page?(module) do
      add_page_call_graph_edges(call_graph, module)
    end

    if Reflection.component?(module) do
      add_component_call_graph_edges(call_graph, module)
    end

    call_graph
  end

  defp remove_module_vertices(call_graph, module) do
    remove_vertices(call_graph, module_vertices(call_graph, module))
  end
end
