defmodule Hologram.Compiler.CallGraph do
  @moduledoc false

  alias Hologram.Commons.PLT
  alias Hologram.Commons.SerializationUtils
  alias Hologram.Commons.TaskUtils
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Digraph
  alias Hologram.Compiler.IR
  alias Hologram.Reflection

  defstruct pid: nil

  @type t :: %CallGraph{pid: pid}

  @type edge :: {vertex, vertex}
  @type vertex :: module | mfa

  # TODO: Determine automatically based on deps annotations next to function implementations
  @erlang_mfa_edges [
    {{:binary, :compile_pattern, 1}, {:erlang, :make_ref, 0}},
    {{:binary, :match, 2}, {:binary, :match, 3}},
    {{:binary, :match, 3}, {:binary, :_aho_corasick_search, 3}},
    {{:binary, :match, 3}, {:binary, :_boyer_moore_search, 4}},
    {{:binary, :match, 3}, {:binary, :_parse_search_opts, 2}},
    {{:binary, :match, 3}, {:binary, :compile_pattern, 1}},
    {{:binary, :matches, 2}, {:binary, :matches, 3}},
    {{:binary, :matches, 3}, {:binary, :_parse_search_opts, 2}},
    {{:binary, :matches, 3}, {:binary, :compile_pattern, 1}},
    {{:binary, :matches, 3}, {:binary, :match, 3}},
    {{:binary, :replace, 3}, {:binary, :replace, 4}},
    {{:binary, :replace, 4}, {:binary, :compile_pattern, 1}},
    {{:binary, :replace, 4}, {:binary, :match, 3}},
    {{:binary, :replace, 4}, {:binary, :split, 3}},
    {{:binary, :replace, 4}, {:erlang, :iolist_to_binary, 1}},
    {{:binary, :split, 2}, {:binary, :split, 3}},
    {{:binary, :split, 3}, {:binary, :_parse_search_opts, 2}},
    {{:binary, :split, 3}, {:binary, :compile_pattern, 1}},
    {{:binary, :split, 3}, {:binary, :match, 3}},
    {{:elixir_aliases, :safe_concat, 1}, {:elixir_aliases, :concat, 1}},
    {{:elixir_locals, :yank, 2}, {:maps, :remove, 2}},
    {{:elixir_utils, :jaro_similarity, 2}, {:unicode_util, :cp, 1}},
    {{:erlang, :"=<", 2}, {:erlang, :<, 2}},
    {{:erlang, :"=<", 2}, {:erlang, :==, 2}},
    {{:erlang, :>=, 2}, {:erlang, :==, 2}},
    {{:erlang, :>=, 2}, {:erlang, :>, 2}},
    {{:erlang, :atom_to_binary, 1}, {:erlang, :atom_to_binary, 2}},
    {{:erlang, :binary_to_atom, 1}, {:erlang, :binary_to_atom, 2}},
    {{:erlang, :binary_to_existing_atom, 1}, {:erlang, :binary_to_atom, 1}},
    {{:erlang, :binary_to_existing_atom, 2}, {:erlang, :binary_to_atom, 2}},
    {{:erlang, :binary_to_integer, 1}, {:erlang, :binary_to_integer, 2}},
    {{:erlang, :convert_time_unit, 3}, {:erlang, :_validate_time_unit, 2}},
    {{:erlang, :error, 1}, {:erlang, :error, 2}},
    {{:erlang, :float_to_list, 2}, {:erlang, :float_to_binary, 2}},
    {{:erlang, :fun_info, 2}, {:erlang, :fun_info, 1}},
    {{:erlang, :integer_to_binary, 1}, {:erlang, :integer_to_binary, 2}},
    {{:erlang, :integer_to_list, 1}, {:erlang, :integer_to_list, 2}},
    {{:erlang, :iolist_to_binary, 1}, {:lists, :flatten, 1}},
    {{:erlang, :is_map_key, 2}, {:maps, :is_key, 2}},
    {{:erlang, :list_to_existing_atom, 1}, {:erlang, :list_to_atom, 1}},
    {{:erlang, :list_to_integer, 1}, {:erlang, :list_to_integer, 2}},
    {{:erlang, :map_get, 2}, {:maps, :get, 2}},
    {{:erlang, :monotonic_time, 1}, {:erlang, :_validate_time_unit, 2}},
    {{:erlang, :monotonic_time, 1}, {:erlang, :convert_time_unit, 3}},
    {{:erlang, :monotonic_time, 1}, {:erlang, :monotonic_time, 0}},
    {{:erlang, :split_binary, 2}, {:erlang, :byte_size, 1}},
    {{:erlang, :system_time, 0}, {:os, :system_time, 0}},
    {{:erlang, :system_time, 1}, {:os, :system_time, 1}},
    {{:erlang, :time_offset, 0}, {:erlang, :monotonic_time, 0}},
    {{:erlang, :time_offset, 0}, {:os, :system_time, 0}},
    {{:erlang, :time_offset, 1}, {:erlang, :_validate_time_unit, 2}},
    {{:erlang, :time_offset, 1}, {:erlang, :convert_time_unit, 3}},
    {{:erlang, :time_offset, 1}, {:erlang, :time_offset, 0}},
    {{:filelib, :safe_relative_path, 2}, {:filename, :join, 1}},
    {{:filelib, :safe_relative_path, 2}, {:filename, :split, 1}},
    {{:filename, :_do_flatten, 2}, {:erlang, :atom_to_list, 1}},
    {{:filename, :basename, 1}, {:erlang, :iolist_to_binary, 1}},
    {{:filename, :basename, 1}, {:filename, :flatten, 1}},
    {{:filename, :basename, 2}, {:erlang, :iolist_to_binary, 1}},
    {{:filename, :basename, 2}, {:filename, :basename, 1}},
    {{:filename, :basename, 2}, {:filename, :flatten, 1}},
    {{:filename, :dirname, 1}, {:erlang, :iolist_to_binary, 1}},
    {{:filename, :dirname, 1}, {:filename, :_dirname_raw, 1}},
    {{:filename, :dirname, 1}, {:filename, :flatten, 1}},
    {{:filename, :extension, 1}, {:erlang, :iolist_to_binary, 1}},
    {{:filename, :extension, 1}, {:filename, :flatten, 1}},
    {{:filename, :flatten, 1}, {:filename, :_do_flatten, 2}},
    {{:filename, :join, 1}, {:filename, :join, 2}},
    {{:filename, :join, 2}, {:erlang, :iolist_to_binary, 1}},
    {{:filename, :join, 2}, {:filename, :flatten, 1}},
    {{:filename, :rootname, 1}, {:erlang, :iolist_to_binary, 1}},
    {{:filename, :rootname, 1}, {:filename, :_rootname_raw, 2}},
    {{:filename, :rootname, 1}, {:filename, :flatten, 1}},
    {{:filename, :rootname, 2}, {:erlang, :iolist_to_binary, 1}},
    {{:filename, :rootname, 2}, {:filename, :_rootname_raw, 2}},
    {{:filename, :rootname, 2}, {:filename, :flatten, 1}},
    {{:filename, :split, 1}, {:erlang, :iolist_to_binary, 1}},
    {{:filename, :split, 1}, {:filename, :flatten, 1}},
    {{:lists, :flatten, 2}, {:lists, :flatten, 1}},
    {{:lists, :seq, 2}, {:lists, :seq, 3}},
    {{:lists, :keymember, 3}, {:lists, :keyfind, 3}},
    {{:lists, :keysort, 2}, {:erlang, :element, 2}},
    {{:maps, :get, 2}, {:maps, :get, 3}},
    {{:maps, :take, 2}, {:maps, :get, 3}},
    {{:maps, :take, 2}, {:maps, :remove, 2}},
    {{:maps, :update, 3}, {:maps, :is_key, 2}},
    {{:maps, :update, 3}, {:maps, :put, 3}},
    {{:os, :system_time, 1}, {:erlang, :_validate_time_unit, 2}},
    {{:os, :system_time, 1}, {:erlang, :convert_time_unit, 3}},
    {{:os, :system_time, 1}, {:os, :system_time, 0}},
    {{:sets, :_validate_opts, 1}, {:lists, :keyfind, 3}},
    {{:sets, :add_element, 2}, {:maps, :put, 3}},
    {{:sets, :del_element, 2}, {:maps, :remove, 2}},
    {{:sets, :fold, 3}, {:maps, :keys, 1}},
    {{:sets, :from_list, 2}, {:maps, :from_keys, 2}},
    {{:sets, :from_list, 2}, {:sets, :_validate_opts, 1}},
    {{:sets, :is_element, 2}, {:maps, :is_key, 2}},
    {{:sets, :is_subset, 2}, {:sets, :is_element, 2}},
    {{:sets, :is_subset, 2}, {:sets, :to_list, 1}},
    {{:sets, :new, 1}, {:sets, :_validate_opts, 1}},
    {{:sets, :size, 1}, {:erlang, :map_size, 1}},
    {{:sets, :to_list, 1}, {:maps, :keys, 1}},
    {{:string, :find, 2}, {:string, :find, 3}},
    {{:string, :find, 3}, {:unicode, :characters_to_binary, 1}},
    {{:string, :length, 1}, {:unicode, :characters_to_binary, 1}},
    {{:string, :length, 1}, {:unicode_util, :gc, 1}},
    {{:string, :replace, 3}, {:string, :replace, 4}},
    {{:string, :replace, 4}, {:unicode, :characters_to_binary, 1}},
    {{:string, :split, 2}, {:string, :split, 3}},
    {{:string, :split, 3}, {:unicode, :characters_to_binary, 1}},
    {{:string, :titlecase, 1}, {:lists, :flatten, 1}},
    {{:string, :titlecase, 1}, {:unicode_util, :cp, 1}},
    {{:unicode, :characters_to_binary, 1}, {:unicode, :characters_to_binary, 3}},
    {{:unicode, :characters_to_binary, 3}, {:lists, :flatten, 1}},
    {{:unicode, :characters_to_list, 1}, {:lists, :flatten, 1}},
    {{:unicode, :characters_to_nfc_binary, 1}, {:unicode, :characters_to_binary, 3}},
    {{:unicode, :characters_to_nfc_list, 1}, {:unicode, :characters_to_nfc_binary, 1}},
    {{:unicode, :characters_to_nfc_list, 1}, {:lists, :flatten, 1}},
    {{:unicode, :characters_to_nfd_binary, 1}, {:unicode, :characters_to_binary, 3}},
    {{:unicode, :characters_to_nfkc_binary, 1}, {:unicode, :characters_to_binary, 3}},
    {{:unicode, :characters_to_nfkd_binary, 1}, {:unicode, :characters_to_binary, 3}},
    {{:unicode_util, :_cpl, 2}, {:unicode_util, :_cpl_1_cont, 1}},
    {{:unicode_util, :_cpl, 2}, {:unicode_util, :_cpl_cont, 2}},
    {{:unicode_util, :_cpl, 2}, {:unicode_util, :_is_cp, 1}},
    {{:unicode_util, :_cpl, 2}, {:unicode_util, :_merge_lcr, 2}},
    {{:unicode_util, :_cpl, 2}, {:unicode_util, :cp, 1}},
    {{:unicode_util, :_cpl_1_cont, 1}, {:unicode_util, :_cpl_1_cont2, 1}},
    {{:unicode_util, :_cpl_1_cont, 1}, {:unicode_util, :_cpl_cont, 2}},
    {{:unicode_util, :_cpl_1_cont, 1}, {:unicode_util, :_is_cp, 1}},
    {{:unicode_util, :_cpl_1_cont2, 1}, {:unicode_util, :_cpl_1_cont3, 1}},
    {{:unicode_util, :_cpl_1_cont2, 1}, {:unicode_util, :_cpl_cont2, 2}},
    {{:unicode_util, :_cpl_1_cont2, 1}, {:unicode_util, :_is_cp, 1}},
    {{:unicode_util, :_cpl_1_cont3, 1}, {:unicode_util, :_cpl_cont3, 2}},
    {{:unicode_util, :_cpl_1_cont3, 1}, {:unicode_util, :_is_cp, 1}},
    {{:unicode_util, :_cpl_cont, 2}, {:unicode_util, :_cpl, 2}},
    {{:unicode_util, :_cpl_cont, 2}, {:unicode_util, :_is_cp, 1}},
    {{:unicode_util, :_cpl_cont, 2}, {:unicode_util, :_merge_lcr, 2}},
    {{:unicode_util, :_cpl_cont, 2}, {:unicode_util, :cp, 1}},
    {{:unicode_util, :_cpl_cont2, 2}, {:unicode_util, :_cpl_1_cont2, 1}},
    {{:unicode_util, :_cpl_cont2, 2}, {:unicode_util, :_is_cp, 1}},
    {{:unicode_util, :_cpl_cont3, 2}, {:unicode_util, :_cpl_1_cont3, 1}},
    {{:unicode_util, :_cpl_cont3, 2}, {:unicode_util, :_is_cp, 1}},
    {{:unicode_util, :cp, 1}, {:unicode_util, :_cpl, 2}},
    {{:unicode_util, :cp, 1}, {:unicode_util, :_is_cp, 1}},
    {{:unicode_util, :gc, 1}, {:unicode_util, :cp, 1}}
  ]

  # These functions are transpiled manually for at least one of the following reasons:
  # * the transpiled output is too large
  # * the transpiled output is deeply nested
  # * the function doesn't make sense on the client side
  # * the function must access the Hologram client runtime
  # * the function has only a client-side implementation
  @manually_ported_elixir_mfas [
    {Cldr.Locale, :language_data, 0},
    {Cldr.Validity.U, :encode_key, 2},
    {Code, :ensure_loaded, 1},
    {Hologram.JS, :call, 4},
    {Hologram.JS, :call_async, 4},
    {Hologram.JS, :exec, 1},
    {Hologram.JS, :get, 3},
    {Hologram.JS, :new, 3},
    {Hologram.JS, :set, 4},
    {Hologram.JS, :typeof, 2},
    {Hologram.Router.Helpers, :asset_path, 1},
    {IO, :inspect, 1},
    {IO, :inspect, 2},
    {IO, :inspect, 3},
    {Kernel, :inspect, 1},
    {Kernel, :inspect, 2},
    {String, :contains?, 2},
    {String, :downcase, 1},
    {String, :downcase, 2},
    {String, :replace, 3},
    {String, :trim, 1},
    {String, :upcase, 1},
    {String, :upcase, 2},
    {URI, :encode, 2}
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
    client_class: [
      {:maps, :get, 2}
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
      {:maps, :get, 3},
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
      {String.Chars, :to_string, 1},
      {:erlang, :binary_to_atom, 1},
      {:lists, :flatten, 1},
      {:lists, :keyfind, 3},
      {:lists, :keymember, 3},
      {:maps, :from_list, 1},
      {:maps, :get, 2},
      {:maps, :get, 3},
      {:maps, :is_key, 2},
      {:maps, :merge, 2},
      {:maps, :put, 3}
    ],
    type_class: [
      {:maps, :get, 3},
      {:maps, :is_key, 2}
    ]
  ]

  @doc """
  Adds an edge between two vertices in the call graph.
  Automatically adds vertices if they don't exist.
  """
  @spec add_edge(t, vertex, vertex) :: t
  def add_edge(%{pid: pid} = call_graph, from_vertex, to_vertex) do
    Agent.cast(pid, &Digraph.add_edge(&1, from_vertex, to_vertex))
    call_graph
  end

  @doc """
  Adds multiple edges to the call graph.
  Automatically adds vertices if they don't exist.
  """
  @spec add_edges(t, [edge]) :: t
  def add_edges(%{pid: pid} = call_graph, edges) do
    Agent.cast(pid, &Digraph.add_edges(&1, edges))
    call_graph
  end

  @doc """
  Adds the vertex to the call graph.
  """
  @spec add_vertex(t, vertex) :: t
  def add_vertex(%{pid: pid} = call_graph, vertex) do
    Agent.cast(pid, &Digraph.add_vertex(&1, vertex))
    call_graph
  end

  @doc """
  Builds a call graph from IR.
  """
  @spec build(t, IR.t(), vertex | nil) :: t
  def build(call_graph, ir, from_vertex \\ nil)

  def build(call_graph, %IR.AtomType{value: value}, from_vertex) do
    if Reflection.alias?(value) do
      add_edge(call_graph, from_vertex, value)
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
    |> maybe_add_protocol_call_graph_edges(module)
    |> maybe_add_struct_call_graph_edges(module)
    |> maybe_add_ecto_schema_call_graph_edges(module)
    |> build(body, module)
  end

  # :erlang.apply/3 is not added to the call graph because the encoder
  # translates it to Interpreter.callNamedFunction() instead of Erlang["apply/3"]().
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

  # :erlang.apply/3 is not added to the call graph because the encoder
  # translates it to Interpreter.callNamedFunction() instead of Erlang["apply/3"]().
  def build(
        call_graph,
        %IR.RemoteFunctionCall{
          module: %IR.AtomType{value: :erlang},
          function: :apply,
          args: [module, function, %IR.ListType{data: args}]
        },
        from_vertex
      ) do
    call_graph
    |> build(module, from_vertex)
    |> build(function, from_vertex)
    |> build(args, from_vertex)
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
  @spec build_for_module(t, PLT.t(), module) :: t
  def build_for_module(call_graph, ir_plt, module) do
    module_def = PLT.get!(ir_plt, module)
    build(call_graph, module_def)
  end

  @doc """
  Returns a clone of the given call graph.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/call_graph/clone_1/README.md
  """
  @spec clone(t) :: t
  def clone(call_graph) do
    graph = get_graph(call_graph)
    start(graph)
  end

  @doc """
  Serializes the call graph and writes it to a file.

  Benchmarks: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/call_graph/dump_2/README.md
  """
  @spec dump(t, String.t()) :: t
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
  @spec edges(t) :: [edge]
  def edges(%{pid: pid}) do
    Agent.get(pid, &Digraph.edges/1, :infinity)
  end

  @doc """
  Returns the underlying %Digraph{} struct containing vertices and edges data.
  """
  @spec get_graph(t) :: Digraph.t()
  def get_graph(%{pid: pid}) do
    Agent.get(pid, & &1, :infinity)
  end

  @doc """
  Checks if an edge exists between two given vertices in the call graph.
  """
  @spec has_edge?(t, vertex, vertex) :: boolean
  def has_edge?(%{pid: pid}, from_vertex, to_vertex) do
    Agent.get(pid, &Digraph.has_edge?(&1, from_vertex, to_vertex), :infinity)
  end

  @doc """
  Checks if the given vertex exists in the call graph.
  """
  @spec has_vertex?(t, vertex) :: boolean
  def has_vertex?(%{pid: pid}, vertex) do
    Agent.get(pid, &Digraph.has_vertex?(&1, vertex), :infinity)
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
  @spec list_page_entry_mfas(module) :: [mfa]
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
  Returns the sorted list of MFAs that are reachable by the given page.
  """
  @spec list_page_mfas(t, module) :: [mfa]
  def list_page_mfas(call_graph, page_module) do
    entry_mfas = list_page_entry_mfas(page_module)
    graph = get_graph(call_graph)

    graph
    |> sorted_reachable_mfas(entry_mfas)
    |> reject_hex_mfas()
    |> add_reflection_mfas_reachable_from_server_inits(page_module, graph)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Lists entry runtime MFAs, which include MFAs used by the client runtime JS classes
  and client MFAs used by all pages and components.
  The returned MFAs are sorted.
  """
  @spec list_runtime_entry_mfas :: [mfa]
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
  @spec list_runtime_mfas(t) :: [mfa]
  def list_runtime_mfas(call_graph) do
    entry_mfas = list_runtime_entry_mfas()

    call_graph
    |> get_graph()
    |> add_edges_for_erlang_functions()
    |> sorted_reachable_mfas(entry_mfas)
    |> reject_hex_mfas()
  end

  @doc """
  Loads the graph from the given dump file.
  """
  @spec load(t, String.t()) :: t
  def load(call_graph, dump_path) do
    graph =
      dump_path
      |> File.read!()
      |> SerializationUtils.deserialize(true)

    put_graph(call_graph, graph)
  end

  @doc """
  Returns the list of Elixir MFAs that are manually ported to JavaScript.
  """
  @spec manually_ported_elixir_mfas :: [mfa]
  def manually_ported_elixir_mfas, do: @manually_ported_elixir_mfas

  @doc """
  Loads the graph from the given dump file if the file exists.
  """
  @spec maybe_load(t, String.t()) :: t
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
  @spec module_vertices(t, module) :: [vertex]
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
  rebuilding the graph paths of modules that have been edited,
  and adding the graph paths of modules that have been added.

  Benchmarks: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/call_graph/patch_3/README.md
  """
  @spec patch(t, PLT.t(), map) :: t
  def patch(call_graph, ir_plt, diff) do
    remove_tasks =
      TaskUtils.async_many(diff.removed_modules, &remove_module_vertices(call_graph, &1))

    update_tasks =
      TaskUtils.async_many(diff.edited_modules, fn module ->
        remote_incoming_edges = remote_incoming_edges(call_graph, module)

        call_graph
        |> remove_module_vertices(module)
        |> build_for_module(ir_plt, module)
        |> add_edges(remote_incoming_edges)
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
  @spec put_graph(t, Digraph.t()) :: t
  def put_graph(%{pid: pid} = call_graph, graph) do
    Agent.cast(pid, fn _state -> graph end)
    call_graph
  end

  @doc """
  Lists MFAs that are reachable from the given call graph vertices.
  Unimplemented protocol implementations are excluded.
  """
  @spec reachable_mfas(Digraph.t(), [vertex]) :: [mfa]
  def reachable_mfas(graph, vertices) do
    graph
    |> Digraph.reachable(vertices)
    |> Enum.filter(fn
      # Some protocol implementations are referenced but not actually implemented, e.g. Collectable.Atom
      {module, _function, _arity} -> Reflection.module?(module)
      _module -> false
    end)
  end

  defp reject_hex_mfas(mfas) do
    Enum.reject(mfas, fn {module, _function, _arity} ->
      module_str = to_string(module)

      module_str == "Elixir.Hex" ||
        String.starts_with?(module_str, "Elixir.Hex.") ||
        String.starts_with?(module_str, "Elixir.Inspect.Hex.") ||
        String.starts_with?(module_str, "Elixir.String.Chars.Hex.")
    end)
  end

  @doc """
  Returns the edges in which the second vertex is either the given module
  or a function from the given module, and the first vertex is a function
  from a different module.
  """
  @spec remote_incoming_edges(t, module) :: [edge]
  def remote_incoming_edges(call_graph, to_module) do
    call_graph
    |> module_vertices(to_module)
    |> Enum.reduce([], fn vertex, acc ->
      call_graph
      |> incoming_edges(vertex)
      |> Enum.filter(fn
        {{from_module, _fun, _arity}, _target} when from_module != to_module -> true
        _fallback -> false
      end)
      |> Enum.concat(acc)
    end)
  end

  @doc """
  Removes call graph vertices for Elixir functions ported manually.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/call_graph/remove_manually_ported_mfas_1/README.md
  """
  @spec remove_manually_ported_mfas(t) :: t
  def remove_manually_ported_mfas(call_graph) do
    remove_vertices(call_graph, @manually_ported_elixir_mfas)
  end

  @doc """
  Removes call graph vertices and edges related to MFAs used by the runtime.

  remove_vertices/2 is slow on very large graphs, and in such cases
  it's faster to rebuild the call graph this way.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/call_graph/remove_runtime_mfas!_2/README.md
  """
  @spec remove_runtime_mfas!(t, [mfa]) :: t
  def remove_runtime_mfas!(%{pid: pid} = call_graph, runtime_mfas) do
    Agent.cast(
      pid,
      fn graph ->
        vertices = Digraph.vertices(graph)
        vertices_map_set = MapSet.new(vertices)

        runtime_mfas_map_set = MapSet.new(runtime_mfas)

        new_vertices =
          vertices_map_set
          |> MapSet.difference(runtime_mfas_map_set)
          |> MapSet.to_list()

        new_outgoing_edges =
          graph
          |> Digraph.edges()
          |> Enum.reject(fn {source, target} ->
            # It's more probable for target vertex (than source vertex) to be in runtime MFAs
            MapSet.member?(runtime_mfas_map_set, target) or
              MapSet.member?(runtime_mfas_map_set, source)
          end)

        Digraph.new()
        |> Digraph.add_vertices(new_vertices)
        |> Digraph.add_edges(new_outgoing_edges)
      end
    )

    call_graph
  end

  @doc """
  Removes the vertex from the call graph.
  """
  @spec remove_vertex(t, vertex) :: t
  def remove_vertex(%{pid: pid} = call_graph, vertex) do
    Agent.cast(pid, &Digraph.remove_vertex(&1, vertex))
    call_graph
  end

  @doc """
  Removes the vertices from the call graph.

  Benchmarks: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/call_graph/remove_vertices_2/README.md
  """
  @spec remove_vertices(t, [vertex]) :: t
  def remove_vertices(%{pid: pid} = call_graph, vertices) do
    Agent.cast(pid, &Digraph.remove_vertices(&1, vertices))
    call_graph
  end

  @doc """
  Returns sorted call graph edges.
  """
  @spec sorted_edges(t) :: [edge]
  def sorted_edges(%{pid: pid}) do
    Agent.get(pid, &Digraph.sorted_edges/1, :infinity)
  end

  @doc """
  Lists MFAs that are reachable from the given call graph vertices.
  Unimplemented protocol implementations are excluded.
  The MFAs returned are sorted.
  """
  @spec sorted_reachable_mfas(Digraph.t(), [vertex]) :: [mfa]
  def sorted_reachable_mfas(graph, vertices) do
    graph
    |> reachable_mfas(vertices)
    |> Enum.sort()
  end

  @doc """
  Returns sorted call graph vertices.
  """
  @spec sorted_vertices(t) :: [vertex]
  def sorted_vertices(%{pid: pid}) do
    Agent.get(pid, &Digraph.sorted_vertices/1, :infinity)
  end

  @doc """
  Starts a new call graph agent with (optional) initial graph.
  """
  @spec start(Digraph.t()) :: t
  def start(graph \\ Digraph.new()) do
    {:ok, pid} = Agent.start_link(fn -> graph end)
    %CallGraph{pid: pid}
  end

  @doc """
  Stops the call graph agent.
  """
  @spec stop(t) :: :ok
  def stop(%{pid: pid}) do
    Agent.stop(pid)
  end

  @doc """
  Returns call graph vertices.
  """
  @spec vertices(t) :: [vertex]
  def vertices(%{pid: pid}) do
    Agent.get(pid, &Digraph.vertices/1, :infinity)
  end

  # Add call graph edges for Erlang functions depending on other Erlang functions.
  # credo:disable-for-next-line Credo.Check.Refactor.ABCSize
  defp add_edges_for_erlang_functions(graph) do
    Digraph.add_edges(graph, @erlang_mfa_edges)
  end

  # TODO: think how to avoid this
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

    edges =
      for impl <- impls,
          {name, arity} <- funs,
          edge <- [
            {{module, name, arity}, {impl, :__impl__, 1}},
            {{module, name, arity}, {impl, name, arity}}
          ] do
        edge
      end

    add_edges(call_graph, edges)
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

  defp incoming_edges(%{pid: pid}, vertex) do
    Agent.get(pid, &Digraph.incoming_edges(&1, vertex), :infinity)
  end

  defp list_reflection_mfas_reachable_from_server_init(templetable, graph) do
    graph
    |> Digraph.reachable([{templetable, :init, 3}])
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
        {module, {module, :__changeset__, 0}},
        {module, {module, :__schema__, 1}},
        {module, {module, :__schema__, 2}}
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
        {module, {module, :__struct__, 0}},
        {module, {module, :__struct__, 1}}
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
