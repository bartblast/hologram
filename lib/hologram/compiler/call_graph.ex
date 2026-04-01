defmodule Hologram.Compiler.CallGraph do
  @moduledoc false

  alias Hologram.Commons.PLT
  alias Hologram.Commons.SerializationUtils
  alias Hologram.Commons.TaskUtils
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.CallGraph.Context
  alias Hologram.Compiler.Digraph
  alias Hologram.Compiler.IR
  alias Hologram.Reflection

  defmodule Context.Modifiers do
    @moduledoc false

    @type t :: %__MODULE__{
            suppress_edges_to_module_vertices?: bool
          }

    defstruct suppress_edges_to_module_vertices?: false
  end

  defmodule Context do
    @moduledoc false

    alias Hologram.Compiler.CallGraph.Context.Modifiers

    @type t :: %__MODULE__{
            from_vertex: module | mfa | nil,
            guard?: bool,
            modifiers: Modifiers.t(),
            pattern?: bool,
            protocol_impl: module | nil
          }

    defstruct from_vertex: nil,
              guard?: false,
              modifiers: %Modifiers{},
              pattern?: false,
              protocol_impl: nil
  end

  defstruct pid: nil

  @type t :: %CallGraph{pid: pid}

  @type edge :: {vertex, vertex}
  @type vertex :: module | mfa

  # Page functions needed by other pages for link building (e.g. in Hologram.UI.Link component).
  @cross_page_funs [{:__params__, 0}, {:__route__, 0}]

  # Edges for dynamic dispatch patterns where the target module is determined at runtime.
  # These edges can't be discovered from static IR analysis.
  @dynamic_dispatch_edges [
    {{Date, :day_of_era, 1}, {Calendar.ISO, :day_of_era, 3}},
    {{Date, :day_of_week, 2}, {Calendar.ISO, :day_of_week, 4}},
    {{Date, :day_of_year, 1}, {Calendar.ISO, :day_of_year, 3}},
    {{Date, :days_in_month, 1}, {Calendar.ISO, :days_in_month, 2}},
    {{Date, :leap_year?, 1}, {Calendar.ISO, :leap_year?, 1}},
    {{Date, :months_in_year, 1}, {Calendar.ISO, :months_in_year, 1}},
    {{Date, :new, 4}, {Calendar.ISO, :valid_date?, 3}},
    {{Date, :quarter_of_year, 1}, {Calendar.ISO, :quarter_of_year, 3}},
    {{Date, :shift, 2}, {Calendar.ISO, :shift_date, 4}},
    {{Date, :to_string, 1}, {Calendar.ISO, :date_to_string, 3}},
    {{Date, :year_of_era, 1}, {Calendar.ISO, :year_of_era, 3}},
    {{DateTime, :from_gregorian_seconds, 3}, {Calendar.ISO, :naive_datetime_from_iso_days, 1}},
    {{DateTime, :from_iso_days, 4}, {Calendar.ISO, :naive_datetime_from_iso_days, 1}},
    {{DateTime, :shift, 3}, {Calendar.ISO, :naive_datetime_to_iso_days, 7}},
    {{DateTime, :shift, 3}, {Calendar.ISO, :shift_naive_datetime, 8}},
    {{DateTime, :shift_by_offset, 2}, {Calendar.ISO, :naive_datetime_from_iso_days, 1}},
    {{DateTime, :shift_zone_for_iso_days_utc, 5},
     {Calendar.ISO, :naive_datetime_from_iso_days, 1}},
    {{Inspect.Date, :inspect, 2}, {Calendar.ISO, :date_to_string, 3}},
    {{Inspect.NaiveDateTime, :inspect, 2}, {Calendar.ISO, :naive_datetime_to_string, 7}},
    {{Inspect.Time, :inspect, 2}, {Calendar.ISO, :time_to_string, 4}},
    {{NaiveDateTime, :beginning_of_day, 1}, {Calendar.ISO, :iso_days_to_beginning_of_day, 1}},
    {{NaiveDateTime, :end_of_day, 1}, {Calendar.ISO, :iso_days_to_end_of_day, 1}},
    {{NaiveDateTime, :from_iso_days, 3}, {Calendar.ISO, :naive_datetime_from_iso_days, 1}},
    {{NaiveDateTime, :new, 8}, {Calendar.ISO, :valid_date?, 3}},
    {{NaiveDateTime, :new, 8}, {Calendar.ISO, :valid_time?, 4}},
    {{NaiveDateTime, :shift, 2}, {Calendar.ISO, :shift_naive_datetime, 8}},
    {{NaiveDateTime, :to_gregorian_seconds, 1}, {Calendar.ISO, :naive_datetime_to_iso_days, 7}},
    {{NaiveDateTime, :to_iso_days, 1}, {Calendar.ISO, :naive_datetime_to_iso_days, 7}},
    {{NaiveDateTime, :to_string, 1}, {Calendar.ISO, :naive_datetime_to_string, 7}},
    {{String.Chars.Date, :to_string, 1}, {Calendar.ISO, :date_to_string, 3}},
    {{String.Chars.NaiveDateTime, :to_string, 1}, {Calendar.ISO, :naive_datetime_to_string, 7}},
    {{String.Chars.Time, :to_string, 1}, {Calendar.ISO, :time_to_string, 4}},
    {{Time, :convert, 2}, {Calendar.ISO, :time_from_day_fraction, 1}},
    {{Time, :from_seconds_after_midnight, 3}, {Calendar.ISO, :time_from_day_fraction, 1}},
    {{Time, :new, 5}, {Calendar.ISO, :valid_time?, 4}},
    {{Time, :shift, 2}, {Calendar.ISO, :shift_time, 5}},
    {{Time, :to_day_fraction, 1}, {Calendar.ISO, :time_to_day_fraction, 4}},
    {{Time, :to_string, 1}, {Calendar.ISO, :time_to_string, 4}}
  ]

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
    {{:erlang, :iolist_to_binary, 1}, {:erlang, :list_to_binary, 1}},
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
    {Application, :get_env, 3},
    {Cldr.Locale, :language_data, 0},
    {Cldr.Validity.U, :encode_key, 2},
    {Code, :ensure_loaded, 1},
    {Hologram.JS, :call, 4},
    {Hologram.JS, :delete, 3},
    {Hologram.JS, :dispatch_event, 5},
    {Hologram.JS, :eval, 1},
    {Hologram.JS, :exec, 1},
    {Hologram.JS, :get, 3},
    {Hologram.JS, :instanceof, 3},
    {Hologram.JS, :new, 3},
    {Hologram.JS, :set, 4},
    {Hologram.JS, :typeof, 2},
    {Hologram.Router.Helpers, :asset_path, 1},
    {IO, :inspect, 1},
    {IO, :inspect, 2},
    {IO, :inspect, 3},
    {IO, :warn, 1},
    {IO, :warn, 2},
    {IO, :warn_once, 3},
    {Kernel, :inspect, 1},
    {Kernel, :inspect, 2},
    {String, :contains?, 2},
    {String, :downcase, 1},
    {String, :downcase, 2},
    {String, :replace, 3},
    {String, :trim, 1},
    {String, :upcase, 1},
    {String, :upcase, 2},
    {Task, :await, 1},
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
    manually_ported_io_module: [
      {:erlang, :iolist_to_binary, 1}
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

  # Erlang functions that must only run on the server (e.g. filesystem, network, OS).
  # Any MFA that transitively calls one of these is pruned from the client bundle.
  @server_only_erlang_mfas [
    {:file, :make_symlink, 2}
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
  Adds call graph edges that can't be discovered from static IR analysis:
  Erlang functions depending on other Erlang functions, and dynamic dispatch
  patterns in Elixir stdlib (e.g. behaviour callbacks called via variable with known default).
  """
  @spec add_non_discoverable_edges(t) :: t
  def add_non_discoverable_edges(%{pid: pid} = call_graph) do
    Agent.cast(pid, fn graph ->
      graph
      |> Digraph.add_edges(@erlang_mfa_edges)
      |> Digraph.add_edges(@dynamic_dispatch_edges)
    end)

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
  @spec build(t, IR.t() | list, Context.t()) :: t

  def build(call_graph, %IR.AtomType{value: value}, %Context{
        from_vertex: from_vertex,
        guard?: false,
        pattern?: false,
        modifiers: %{suppress_edges_to_module_vertices?: false}
      }) do
    if Reflection.alias?(value) do
      add_edge(call_graph, from_vertex, value)
    end

    call_graph
  end

  def build(call_graph, %IR.AtomType{}, _context), do: call_graph

  def build(
        call_graph,
        %IR.Clause{match: match, guards: guards, body: body},
        context
      ) do
    call_graph
    |> build(match, %{context | pattern?: true})
    |> build(guards, %{context | guard?: true})
    |> build(body, %{context | pattern?: false})
  end

  def build(
        call_graph,
        %IR.FunctionClause{params: params, guards: guards, body: body},
        context
      ) do
    call_graph
    |> build(params, %{context | pattern?: true})
    |> build(guards, %{context | guard?: true})
    |> build(body, %{context | pattern?: false})
  end

  # Suppress module vertex edges in __impl__/1 clause body. This function is generated by
  # defimpl and its body contains module atoms (the :for and :protocol values) that are
  # metadata, not real dependencies. Without this, reaching any protocol implementation
  # would pull in the target module's entire function tree via the AtomType handler.
  # MFA edges are not affected.
  def build(
        call_graph,
        %IR.FunctionDefinition{name: :__impl__, arity: 1, clause: clause},
        %Context{from_vertex: from_vertex} = context
      ) do
    fun_def_vertex = {from_vertex, :__impl__, 1}

    new_context = %{
      context
      | from_vertex: fun_def_vertex,
        modifiers: %{context.modifiers | suppress_edges_to_module_vertices?: true}
    }

    call_graph
    |> add_edge(from_vertex, fun_def_vertex)
    |> build(clause, new_context)
  end

  # Suppress module vertex edges in __protocol__/1 clause body. This function is generated
  # by defprotocol and its body contains module atoms (consolidated implementations, the
  # protocol module) that are metadata, not real dependencies. Without this, reaching any
  # protocol function would pull in every consolidated implementation module's entire
  # function tree. MFA edges are not affected.
  def build(
        call_graph,
        %IR.FunctionDefinition{name: :__protocol__, arity: 1, clause: clause},
        %Context{from_vertex: from_vertex} = context
      ) do
    fun_def_vertex = {from_vertex, :__protocol__, 1}

    new_context = %{
      context
      | from_vertex: fun_def_vertex,
        modifiers: %{context.modifiers | suppress_edges_to_module_vertices?: true}
    }

    call_graph
    |> add_edge(from_vertex, fun_def_vertex)
    |> build(clause, new_context)
  end

  # Suppress module vertex edges in __struct__/0 and __struct__/1 clause bodies. These
  # functions are generated by defstruct and their bodies contain module atoms as default
  # field values in the struct map (e.g. calendar: Calendar.ISO in Date). These are data
  # defaults, not real dependencies. Without this, any struct with a module atom as a default
  # value would pull in that module's entire function tree. MFA edges (Enum.reduce/3,
  # Map.merge/2, etc.) are not affected.
  def build(
        call_graph,
        %IR.FunctionDefinition{name: :__struct__, arity: arity, clause: clause},
        %Context{from_vertex: from_vertex} = context
      )
      when arity in [0, 1] do
    fun_def_vertex = {from_vertex, :__struct__, arity}

    new_context = %{
      context
      | from_vertex: fun_def_vertex,
        modifiers: %{context.modifiers | suppress_edges_to_module_vertices?: true}
    }

    call_graph
    |> add_edge(from_vertex, fun_def_vertex)
    |> build(clause, new_context)
  end

  # Suppress module vertex edges in impl_for/1 clause body. This function is generated by
  # defprotocol and its body contains module atoms for ALL implementation modules (return
  # values for type-based dispatch). Without this, every implementation module vertex would
  # be reached, pulling in their entire function trees. MFA edges (struct_impl_for/1 local
  # call in the struct dispatch clause) are not affected. The actual protocol dispatch is
  # handled by add_protocol_call_graph_edges/2.
  def build(
        call_graph,
        %IR.FunctionDefinition{name: :impl_for, arity: 1, clause: clause},
        %Context{from_vertex: from_vertex} = context
      ) do
    fun_def_vertex = {from_vertex, :impl_for, 1}

    new_context = %{
      context
      | from_vertex: fun_def_vertex,
        modifiers: %{context.modifiers | suppress_edges_to_module_vertices?: true}
    }

    call_graph
    |> add_edge(from_vertex, fun_def_vertex)
    |> build(clause, new_context)
  end

  # Suppress module vertex edges in impl_for!/1 clause body. This function is generated by
  # defprotocol and its body contains a self-referential module atom (__MODULE__ in the
  # Protocol.UndefinedError message). Without this, reaching impl_for!/1 would pull in
  # the protocol module vertex, making ALL protocol functions and ALL their implementations
  # reachable. MFA edges (impl_for/1 local call, :erlang.error/1, etc.) are not affected.
  # The actual protocol dispatch is handled by add_protocol_call_graph_edges/2.
  def build(
        call_graph,
        %IR.FunctionDefinition{name: :impl_for!, arity: 1, clause: clause},
        %Context{from_vertex: from_vertex} = context
      ) do
    fun_def_vertex = {from_vertex, :impl_for!, 1}

    new_context = %{
      context
      | from_vertex: fun_def_vertex,
        modifiers: %{context.modifiers | suppress_edges_to_module_vertices?: true}
    }

    call_graph
    |> add_edge(from_vertex, fun_def_vertex)
    |> build(clause, new_context)
  end

  # Suppress module vertex edges in struct_impl_for/1 clause body. This function is generated
  # by defprotocol and its body contains module atoms for ALL struct-based implementation
  # modules (both as pattern matches and return values). Without this, every struct
  # implementation module vertex would be reached, pulling in their entire function trees.
  # MFA edges (Module.concat/2, Code.ensure_compiled/1 in non-consolidated protocols) are
  # not affected. The actual protocol dispatch is handled by add_protocol_call_graph_edges/2.
  def build(
        call_graph,
        %IR.FunctionDefinition{name: :struct_impl_for, arity: 1, clause: clause},
        %Context{from_vertex: from_vertex} = context
      ) do
    fun_def_vertex = {from_vertex, :struct_impl_for, 1}

    new_context = %{
      context
      | from_vertex: fun_def_vertex,
        modifiers: %{context.modifiers | suppress_edges_to_module_vertices?: true}
    }

    call_graph
    |> add_edge(from_vertex, fun_def_vertex)
    |> build(clause, new_context)
  end

  # Suppress module vertex edges in count/1, member?/2, and slice/1 clause bodies in
  # Enumerable protocol implementations. The Enumerable protocol convention requires these
  # functions to return {:error, __MODULE__} when deferring to the default implementation.
  # The __MODULE__ atom creates a module vertex edge that pulls in all sibling functions
  # (including reduce/3 which can cascade heavily). MFA edges are not affected. The actual
  # protocol dispatch is already handled by add_protocol_call_graph_edges/2.
  def build(
        call_graph,
        %IR.FunctionDefinition{name: name, arity: arity, clause: clause},
        %Context{from_vertex: from_vertex} = context
      )
      when (name == :count and arity == 1) or
             (name == :member? and arity == 2) or
             (name == :slice and arity == 1) do
    fun_def_vertex = {from_vertex, name, arity}
    call_graph = add_edge(call_graph, from_vertex, fun_def_vertex)

    new_context =
      if context.protocol_impl == Enumerable do
        %{
          context
          | from_vertex: fun_def_vertex,
            modifiers: %{context.modifiers | suppress_edges_to_module_vertices?: true}
        }
      else
        %{context | from_vertex: fun_def_vertex}
      end

    build(call_graph, clause, new_context)
  end

  def build(
        call_graph,
        %IR.FunctionDefinition{name: name, arity: arity, clause: clause},
        %Context{from_vertex: from_vertex} = context
      ) do
    fun_def_vertex = {from_vertex, name, arity}

    call_graph
    |> add_edge(from_vertex, fun_def_vertex)
    |> build(clause, %{context | from_vertex: fun_def_vertex})
  end

  def build(
        call_graph,
        %IR.LocalFunctionCall{function: function, args: args},
        %Context{from_vertex: {module, _function, _arity}} = context
      ) do
    to_vertex = {module, function, Enum.count(args)}

    call_graph
    |> add_edge(context.from_vertex, to_vertex)
    |> build(args, context)
  end

  def build(call_graph, %IR.MatchOperator{left: left, right: right}, context) do
    call_graph
    |> build(left, %{context | pattern?: true})
    |> build(right, context)
  end

  def build(
        call_graph,
        %IR.ModuleDefinition{module: %IR.AtomType{value: module}, body: body},
        context
      ) do
    new_context = %{
      context
      | from_vertex: module,
        protocol_impl: Reflection.protocol_impl(module)
    }

    call_graph
    |> maybe_add_protocol_call_graph_edges(module)
    |> maybe_add_struct_call_graph_edges(module)
    |> maybe_add_ecto_schema_call_graph_edges(module)
    |> build(body, new_context)
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
        context
      ) do
    to_vertex = {module, function, Enum.count(args)}
    add_edge(call_graph, context.from_vertex, to_vertex)

    build(call_graph, args, context)
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
        context
      ) do
    call_graph
    |> build(module, context)
    |> build(function, context)
    |> build(args, context)
  end

  # Suppress module vertex edges in the third argument (error options) of :erlang.error/3.
  # The Elixir compiler transforms `raise` into :erlang.error/3 with
  # error_info: %{module: Exception} as the third argument. This Exception
  # module atom is compiler-injected metadata for error formatting, not a
  # real dependency. Without this, every `raise` would pull in the Exception
  # module's entire function tree (58 functions). MFA edges are not affected.
  def build(
        call_graph,
        %IR.RemoteFunctionCall{
          module: %IR.AtomType{value: :erlang},
          function: :error,
          args: [reason, args, error_options]
        },
        context
      ) do
    add_edge(call_graph, context.from_vertex, {:erlang, :error, 3})

    suppressed_context = %{
      context
      | modifiers: %{context.modifiers | suppress_edges_to_module_vertices?: true}
    }

    call_graph
    |> build(reason, context)
    |> build(args, context)
    |> build(error_options, suppressed_context)
  end

  # Skip module atoms in the first argument (deduplication key) of IO.warn_once/3.
  # The key is typically a tuple like {ModuleName, some_value} used to track
  # whether a warning has already been printed. The module atom in the key is
  # a namespace identifier, not a real dependency. Without this, any module
  # calling IO.warn_once with its own name as a key would pull in its entire
  # function tree via the module vertex.
  # Non-atom elements in the key are still traversed to capture any function call edges.
  def build(
        call_graph,
        %IR.RemoteFunctionCall{
          module: %IR.AtomType{value: IO},
          function: :warn_once,
          args: [key, message, stacktrace_depth]
        },
        context
      ) do
    add_edge(call_graph, context.from_vertex, {IO, :warn_once, 3})

    suppressed_context = %{
      context
      | modifiers: %{context.modifiers | suppress_edges_to_module_vertices?: true}
    }

    call_graph
    |> build(key, suppressed_context)
    |> build(message, context)
    |> build(stacktrace_depth, context)
  end

  # Suppress module vertex edges in Kernel.inspect/1,2 first argument. Module atoms passed
  # to inspect are used for string formatting (e.g. in error messages), not as real
  # dependencies. Without this, code like `inspect(MyModule)` in error paths would pull in
  # MyModule's entire function tree. MFA edges are not affected. The second argument
  # (options) is traversed normally.
  def build(
        call_graph,
        %IR.RemoteFunctionCall{
          module: %IR.AtomType{value: Kernel},
          function: :inspect,
          args: [term | opts]
        },
        context
      ) do
    to_vertex = {Kernel, :inspect, 1 + length(opts)}
    add_edge(call_graph, context.from_vertex, to_vertex)

    suppressed_context = %{
      context
      | modifiers: %{context.modifiers | suppress_edges_to_module_vertices?: true}
    }

    call_graph
    |> build(term, suppressed_context)
    |> build(opts, context)
  end

  # For Kernel.struct!/2 with a literal module atom as the first argument, create targeted
  # edges to {module, :__struct__, 0} and {module, :__struct__, 1} instead of the module
  # vertex. Kernel.struct!/2 only uses the module to call __struct__/0 and __struct__/1.
  # This is the same approach as the __struct__ key-in-map special case. Without this,
  # every defexception module's exception/1 function (which calls Kernel.struct!(__MODULE__,
  # args)) would pull in the module's entire function tree.
  def build(
        call_graph,
        %IR.RemoteFunctionCall{
          module: %IR.AtomType{value: Kernel},
          function: :struct!,
          args: [%IR.AtomType{value: module}, fields]
        },
        context
      ) do
    call_graph
    |> add_edge(context.from_vertex, {Kernel, :struct!, 2})
    |> add_edge(context.from_vertex, {module, :__struct__, 0})
    |> add_edge(context.from_vertex, {module, :__struct__, 1})
    |> build(fields, context)
  end

  # Suppress module vertex edges in the :protocol key value of
  # Protocol.UndefinedError.exception/1 args. This is expanded from:
  # raise Protocol.UndefinedError, protocol: SomeProtocol, value: data
  # The protocol module atom is just metadata identifying the protocol in the error message,
  # not a real dependency. Without this, raising Protocol.UndefinedError in protocol
  # implementation fallback clauses would pull in the protocol module's entire function tree.
  # MFA edges are not affected. Other keyword entries (e.g. :value, :description) are
  # traversed normally.
  def build(
        call_graph,
        %IR.RemoteFunctionCall{
          module: %IR.AtomType{value: Protocol.UndefinedError},
          function: :exception,
          args: [%IR.ListType{data: data}]
        },
        context
      ) do
    add_edge(call_graph, context.from_vertex, {Protocol.UndefinedError, :exception, 1})

    suppressed_context = %{
      context
      | modifiers: %{context.modifiers | suppress_edges_to_module_vertices?: true}
    }

    Enum.each(data, fn
      %IR.TupleType{data: [%IR.AtomType{value: :protocol}, module]} ->
        build(call_graph, module, suppressed_context)

      entry ->
        build(call_graph, entry, context)
    end)

    call_graph
  end

  def build(
        call_graph,
        %IR.RemoteFunctionCall{
          module: %IR.AtomType{value: module},
          function: function,
          args: args
        },
        context
      ) do
    to_vertex = {module, function, Enum.count(args)}
    add_edge(call_graph, context.from_vertex, to_vertex)

    build(call_graph, args, context)
  end

  def build(
        call_graph,
        %IR.TryCatchClause{kind: kind, value: value, guards: guards, body: body},
        context
      ) do
    call_graph
    |> build(kind, context)
    |> build(value, %{context | pattern?: true})
    |> build(guards, %{context | guard?: true})
    |> build(body, context)
  end

  # Rescue clause exception modules are used for pattern matching against exception types,
  # not as module dependencies. Without this, rescuing UndefinedFunctionError (as Access.get/3
  # and Access.fetch/2 do) would pull in the entire UndefinedFunctionError function tree
  # (blame/2, hint/4, exports_for/1, etc.).
  def build(
        call_graph,
        %IR.TryRescueClause{variable: variable, modules: modules, body: body},
        context
      ) do
    call_graph
    |> build(variable, %{context | pattern?: true})
    |> build(modules, %{context | pattern?: true})
    |> build(body, context)
  end

  def build(call_graph, list, context) when is_list(list) do
    Enum.each(list, &build(call_graph, &1, context))
    call_graph
  end

  def build(call_graph, map, context) when is_map(map) do
    map
    |> Map.to_list()
    |> Enum.each(fn {key, value} ->
      build(call_graph, key, context)
      build(call_graph, value, context)
    end)

    call_graph
  end

  # For __struct__ key in map data, create targeted edges to __struct__/0 and __struct__/1
  # instead of to the module vertex, to avoid pulling in the module's entire function tree.
  def build(call_graph, {%IR.AtomType{value: :__struct__}, %IR.AtomType{value: module}}, %Context{
        from_vertex: from_vertex,
        guard?: false,
        pattern?: false
      }) do
    if Reflection.alias?(module) do
      call_graph
      |> add_edge(from_vertex, {module, :__struct__, 0})
      |> add_edge(from_vertex, {module, :__struct__, 1})
    else
      call_graph
    end
  end

  def build(call_graph, {%IR.AtomType{value: :__struct__}, _value}, _context), do: call_graph

  def build(call_graph, tuple, context) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.each(&build(call_graph, &1, context))

    call_graph
  end

  def build(call_graph, _ir, _context), do: call_graph

  @doc """
  Builds a call graph from a module definition IR located in the given IR PLT.
  """
  @spec build_for_module(t, PLT.t(), module) :: t
  def build_for_module(call_graph, ir_plt, module) do
    module_def = PLT.get!(ir_plt, module)
    build(call_graph, module_def, %Context{})
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
  Computes cascade entries for module vertices in a call graph.

  Returns a list of `{source, module, downstream_mfa_count}` tuples sorted by
  downstream MFA count (biggest cascades first).
  """
  @spec compute_cascades(Digraph.t(), MapSet.t(), MapSet.t()) :: [
          {vertex, vertex, non_neg_integer}
        ]
  def compute_cascades(graph, module_vertices, reachable) do
    module_vertices
    |> Enum.flat_map(fn module ->
      downstream_mfa_count =
        graph
        |> Digraph.reachable([module])
        |> Enum.count(&match?({_module, _function, _arity}, &1))

      graph
      |> Digraph.incoming_edges(module)
      |> Enum.map(&elem(&1, 0))
      |> Enum.filter(&MapSet.member?(reachable, &1))
      |> Enum.map(fn source -> {source, module, downstream_mfa_count} end)
    end)
    |> Enum.sort_by(fn {_source, _module, count} -> count end, :desc)
  end

  @doc """
  For each given sink MFA, counts how many MFAs from the reachable set can reach it.

  Returns a list of `{mfa, reaching_count}` tuples sorted by reaching count
  (biggest sinks first).
  """
  @spec compute_sink_reaching_counts(Digraph.t(), [mfa], MapSet.t()) :: [
          {mfa, non_neg_integer}
        ]
  def compute_sink_reaching_counts(graph, sink_mfas, reachable) do
    sink_mfas
    |> Enum.map(fn mfa ->
      reaching_count =
        graph
        |> Digraph.reaching([mfa], opaque_vertex?: &is_atom/1)
        |> Enum.count(fn
          {_module, _function, _arity} = vertex -> MapSet.member?(reachable, vertex)
          _module -> false
        end)

      {mfa, reaching_count}
    end)
    |> Enum.sort_by(fn {_mfa, count} -> count end, :desc)
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
  Returns a MapSet of MFAs that transitively call `Task.await/1`.

  Must be called on the original call graph before `remove_manually_ported_mfas/1`
  strips the `Task.await/1` vertex.
  """
  @spec list_async_mfas(t) :: MapSet.t(mfa)
  def list_async_mfas(call_graph) do
    graph = get_graph(call_graph)

    graph
    |> Digraph.reaching([{Task, :await, 1}], opaque_vertex?: &is_atom/1)
    # Excludes bare module atom vertices, keeping only MFA tuples.
    # No Reflection.module?/1 guard needed in the filter (unlike reachable_mfas/2) because
    # the result is only used for MapSet.member? lookups against already-included MFAs.
    |> Enum.filter(&is_tuple/1)
    |> MapSet.new()
  end

  @doc """
  Returns the sorted list of MFAs that are reachable by the given page.
  """
  @spec list_page_mfas(t, module) :: [mfa]
  def list_page_mfas(call_graph, page_module) do
    graph = get_graph(call_graph)

    graph
    |> remove_other_pages_mfas(page_module)
    |> sorted_reachable_mfas([page_module])
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
    |> Enum.reduce(
      @mfas_used_by_all_pages_and_components,
      fn {_key, mfas}, acc ->
        mfas ++ acc
      end
    )
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

    refresh_protocol_dispatch_edges(call_graph, diff.added_modules ++ diff.edited_modules)

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
  Removes other pages' MFAs from the digraph,
  keeping only cross-page functions (__params__/0, __route__/0).
  """
  @spec remove_other_pages_mfas(Digraph.t(), module) :: Digraph.t()
  def remove_other_pages_mfas(%Digraph{} = graph, page_module) do
    other_page_modules =
      Reflection.list_pages()
      |> Enum.reject(&(&1 == page_module))
      |> MapSet.new()

    other_page_vertices =
      graph
      |> Digraph.vertices()
      |> Enum.filter(fn
        {module, fun, arity} ->
          MapSet.member?(other_page_modules, module) &&
            {fun, arity} not in @cross_page_funs

        _fallback ->
          false
      end)

    Digraph.remove_vertices(graph, other_page_vertices)
  end

  @doc """
  Removes other pages' MFAs from the call graph,
  keeping only cross-page functions (__params__/0, __route__/0).
  """
  @spec remove_other_pages_mfas!(t, module) :: t
  def remove_other_pages_mfas!(%{pid: pid} = call_graph, page_module) do
    Agent.cast(pid, &remove_other_pages_mfas(&1, page_module))

    call_graph
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
  Removes server-only MFAs from the call graph:
  * command/3 and init/3 for templatable modules (pages and components)
  * server-only Erlang MFAs (e.g. filesystem operations) and all MFAs
    that transitively call them

  Protocol dispatch edges are not traversed backwards, so if only one
  protocol implementation calls a server-only function, only that
  implementation is removed - not the protocol function or its other callers.
  """
  @spec remove_server_only_mfas!(t) :: t
  # credo:disable-for-lines:28 Credo.Check.Refactor.Nesting
  def remove_server_only_mfas!(%{pid: pid} = call_graph) do
    Agent.cast(pid, fn graph ->
      graph = remove_templatable_server_callbacks(graph)

      existing_sinks =
        Enum.filter(@server_only_erlang_mfas, &Digraph.has_vertex?(graph, &1))

      if existing_sinks == [] do
        graph
      else
        protocol_vertices = list_protocol_vertices(graph)

        vertices_to_remove =
          graph
          |> Digraph.reaching(existing_sinks,
            opaque_vertices: protocol_vertices,
            opaque_vertex?: &is_atom/1
          )
          |> Enum.filter(fn vertex ->
            is_tuple(vertex) && !MapSet.member?(protocol_vertices, vertex)
          end)

        Digraph.remove_vertices(graph, vertices_to_remove)
      end
    end)

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

  defp list_protocol_vertices(graph) do
    graph
    |> Digraph.vertices()
    |> Enum.filter(fn
      {module, _fun, _arity} -> Reflection.protocol?(module)
      _other -> false
    end)
    |> MapSet.new()
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

  # When modules that are protocol implementations are added or edited, the protocol
  # module itself (e.g. Enumerable) is unchanged and not re-processed by patch. Its
  # dispatch edges remain stale. This function re-runs add_protocol_call_graph_edges
  # for each affected protocol so dispatch edges reflect the current set of implementations.
  # Removed modules are excluded because add_protocol_call_graph_edges auto-creates vertices,
  # which would re-introduce vertices that remove_module_vertices already cleaned up.
  defp refresh_protocol_dispatch_edges(call_graph, added_or_edited_modules) do
    added_or_edited_modules
    |> Enum.map(&Reflection.protocol_impl/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.each(&add_protocol_call_graph_edges(call_graph, &1))
  end

  defp remove_module_vertices(call_graph, module) do
    remove_vertices(call_graph, module_vertices(call_graph, module))
  end

  defp remove_templatable_server_callbacks(graph) do
    server_only_vertices =
      graph
      |> Digraph.vertices()
      |> Enum.filter(fn
        {module, :command, 3} -> Reflection.templatable?(module)
        {module, :init, 3} -> Reflection.templatable?(module)
        _fallback -> false
      end)

    Digraph.remove_vertices(graph, server_only_vertices)
  end
end
