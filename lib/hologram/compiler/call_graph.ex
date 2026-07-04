defmodule Hologram.Compiler.CallGraph do
  @moduledoc false

  alias Hologram.Commons.PLT
  alias Hologram.Commons.SerializationUtils
  alias Hologram.Commons.TaskUtils
  alias Hologram.Commons.Types, as: T
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Digraph
  alias Hologram.Compiler.IR
  alias Hologram.Realtime
  alias Hologram.Reflection

  defstruct pid: nil

  @type t :: %CallGraph{pid: pid}

  @type edge :: {vertex, vertex}

  @type server_callback_analysis :: %{
          dispatch_types: MapSet.t(module),
          reflection_mfas: [mfa]
        }

  @type vertex :: module | mfa

  # A literal empty `MapSet.new()` in the initial state reads as concrete and won't unify
  # with the opaque `MapSet.t()` inferred for the state fields.
  @dialyzer {:no_opaque, {:start_reachable_state, 3}}

  # Functions that broadcast action params from arbitrary server code to connected clients.
  @broadcast_action_mfas [
    {Realtime, :broadcast_action, 2},
    {Realtime, :broadcast_action, 3},
    {Realtime, :broadcast_action_except, 3},
    {Realtime, :broadcast_action_except, 4}
  ]

  # Types that consolidated protocols can dispatch on besides structs.
  @built_in_protocol_types [
    Any,
    Atom,
    BitString,
    Float,
    Function,
    Integer,
    List,
    Map,
    PID,
    Port,
    Reference,
    Tuple
  ]

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
    {{DateTime, :to_iso_days, 1}, {Calendar.ISO, :naive_datetime_to_iso_days, 7}},
    {{DateTime, :to_string, 1}, {Calendar.ISO, :datetime_to_string, 11}},
    {{Inspect.Date, :inspect, 2}, {Calendar.ISO, :date_to_string, 3}},
    {{Inspect.DateTime, :inspect, 2}, {Calendar.ISO, :datetime_to_string, 11}},
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
    {{String.Chars.DateTime, :to_string, 1}, {Calendar.ISO, :datetime_to_string, 11}},
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
    {{:string, :jaro_similarity, 2}, {:string, :to_graphemes, 1}},
    {{:string, :length, 1}, {:unicode, :characters_to_binary, 1}},
    {{:string, :length, 1}, {:unicode_util, :gc, 1}},
    {{:string, :replace, 3}, {:string, :replace, 4}},
    {{:string, :replace, 4}, {:unicode, :characters_to_binary, 1}},
    {{:string, :split, 2}, {:string, :split, 3}},
    {{:string, :split, 3}, {:unicode, :characters_to_binary, 1}},
    {{:string, :titlecase, 1}, {:lists, :flatten, 1}},
    {{:string, :titlecase, 1}, {:unicode_util, :cp, 1}},
    {{:string, :to_graphemes, 1}, {:unicode_util, :gc, 1}},
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
      {Exception, :normalize, 2},
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
  Returns the set of types that can appear at protocol dispatch anywhere in an
  app with the given pages: types reachable from the client code of the pages,
  types created in server-executed code of the pages and their components, and
  types reachable from action broadcasting code.
  """
  @spec app_protocol_dispatch_types(Digraph.t(), [module]) :: MapSet.t(module)
  def app_protocol_dispatch_types(graph, pages) do
    # Independent of the client and server traversal chain below, so it runs concurrently.
    broadcast_types_task = Task.async(fn -> broadcast_caller_protocol_dispatch_types(graph) end)

    page_entry_mfas = Enum.flat_map(pages, &list_page_entry_mfas/1)

    page_vertices =
      Digraph.reachable(graph, page_entry_mfas, opaque_vertex?: &protocol_function_mfa?/1)

    components =
      page_vertices
      |> Enum.filter(&match?({_module, _function, _arity}, &1))
      |> extract_uniq_components()

    client_types = protocol_dispatch_types(page_vertices)
    server_types = server_protocol_dispatch_types(graph, pages ++ components)
    broadcast_types = Task.await(broadcast_types_task, :infinity)

    client_types
    |> MapSet.union(server_types)
    |> MapSet.union(broadcast_types)
  end

  @doc """
  Returns the set of types that can appear at protocol dispatch in code of
  functions that broadcast actions to connected clients, i.e. code reachable
  from the callers of Hologram.Realtime.broadcast_action/2, broadcast_action/3,
  broadcast_action_except/3, and broadcast_action_except/4.
  Protocol function vertices are opaque during the traversal, so consolidated
  dispatch edges don't make every loaded implementation's type count as reachable.
  """
  @spec broadcast_caller_protocol_dispatch_types(Digraph.t()) :: MapSet.t(module)
  def broadcast_caller_protocol_dispatch_types(graph) do
    caller_vertices =
      for broadcast_mfa <- @broadcast_action_mfas,
          {caller_vertex, _broadcast_mfa} <- Digraph.incoming_edges(graph, broadcast_mfa) do
        caller_vertex
      end

    graph
    |> Digraph.reachable(caller_vertices, opaque_vertex?: &protocol_function_mfa?/1)
    |> protocol_dispatch_types()
  end

  @doc """
  Builds a call graph from IR.
  """
  @spec build(t, IR.t() | list | map | tuple, vertex | nil) :: t
  def build(call_graph, ir, from_vertex \\ nil)

  def build(call_graph, %IR.AtomType{value: value}, from_vertex) do
    if Reflection.alias?(value) && !protocol_metadata_mfa?(from_vertex) do
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
  @spec clone(t, T.opts()) :: t
  def clone(call_graph, opts \\ []) do
    graph = get_graph(call_graph)

    opts
    |> Keyword.put(:graph, graph)
    |> start()
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
  Server dispatch types and reflection MFAs of the page's templatables are
  looked up in the given precomputed server callback analysis.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/call_graph/list_page_mfas_3/README.md
  """
  @spec list_page_mfas(t, module, %{module => server_callback_analysis}) :: [mfa]
  def list_page_mfas(call_graph, page_module, server_callback_analysis_by_templatable) do
    entry_mfas = list_page_entry_mfas(page_module)
    graph = get_graph(call_graph)

    initial_state = start_reachable_state(graph, entry_mfas, MapSet.new())
    initial_mfas = Enum.filter(initial_state.reached_vertices, &is_tuple/1)
    templatables = [page_module | extract_uniq_components(initial_mfas)]

    server_types =
      Enum.reduce(templatables, MapSet.new(), fn templatable, acc ->
        MapSet.union(acc, server_callback_analysis_by_templatable[templatable].dispatch_types)
      end)

    final_state = expand_reachable_state_with_types(graph, initial_state, server_types)

    graph
    |> finalize_reachable_mfas(final_state)
    |> reject_hex_mfas()
    |> add_reflection_mfas_reachable_from_server_inits(
      page_module,
      server_callback_analysis_by_templatable
    )
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
  Lists MFAs required by the runtime JS script of an app with the given pages.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/call_graph/list_runtime_mfas_2/README.md
  """
  @spec list_runtime_mfas(t, [module]) :: [mfa]
  def list_runtime_mfas(call_graph, pages) do
    entry_mfas = list_runtime_entry_mfas()
    graph = get_graph(call_graph)

    app_types = app_protocol_dispatch_types(graph, pages)

    graph
    |> reachable_mfas(entry_mfas, app_types)
    |> reject_hex_mfas()
    |> Enum.sort()
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
  Returns the vertices needed by the dispatch mechanism of the protocol functions
  present among the given call graph vertices: the same-module dispatch helpers
  (e.g. impl_for/1, impl_for!/1, struct_impl_for/1) and their dependencies.
  Protocol function vertices are opaque during the traversal, so consolidated
  dispatch edges don't pull protocol implementations.
  """
  @spec protocol_dispatch_dependency_vertices(Digraph.t(), [vertex]) :: [vertex]
  def protocol_dispatch_dependency_vertices(graph, vertices) do
    helper_entry_vertices =
      for vertex <- vertices,
          protocol_function_mfa?(vertex),
          {_source_vertex, target_vertex} <- Digraph.outgoing_edges(graph, vertex),
          protocol_dispatch_helper_mfa?(vertex, target_vertex) do
        target_vertex
      end

    Digraph.reachable(graph, helper_entry_vertices, opaque_vertex?: &protocol_function_mfa?/1)
  end

  # TODO: include types declared via the client-side MFA whitelisting feature once it exists.
  @doc """
  Returns the set of types that can appear at protocol dispatch in the code
  represented by the given call graph vertices.
  The set includes the built-in protocol dispatch types, the struct modules among
  module vertices, and the modules of __struct__/0 and __struct__/1 MFAs.
  """
  @spec protocol_dispatch_types([vertex]) :: MapSet.t(module)
  def protocol_dispatch_types(vertices) do
    @built_in_protocol_types
    |> MapSet.new()
    |> put_protocol_dispatch_types(vertices)
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
  Lists MFAs that are reachable from the given call graph vertices with bounded
  protocol dispatch. Protocol function vertices are opaque during the traversal,
  and a protocol implementation is entered only when its target type is in the
  reachable type set: protocol_dispatch_types/1 of the reached vertices merged
  with the given extra types. The traversal iterates until no new implementations
  become reachable, since entered implementation code can make further types and
  protocols reachable. Dispatch helper vertices are retained via
  protocol_dispatch_dependency_vertices/2.
  Unimplemented protocol implementations are excluded.
  These are the semantics for computing what ships to the client for a concrete
  app, whose code bounds the types that can occur at protocol dispatch. For
  app-agnostic analyses, where any implementation could be exercised, see
  unbounded_reachable_mfas/2.
  """
  @spec reachable_mfas(Digraph.t(), [vertex], MapSet.t(module)) :: [mfa]
  def reachable_mfas(graph, entry_vertices, extra_types \\ MapSet.new()) do
    state = start_reachable_state(graph, entry_vertices, extra_types)
    finalize_reachable_mfas(graph, state)
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
  Returns the server callback analysis of each given templatable module: the
  protocol dispatch types that can appear in its server-executed code (code
  reachable from its init/3 and command/3 callbacks) and the reflection MFAs
  reachable from its init/3.
  Templatables are analyzed in parallel.
  """
  @spec server_callback_analysis_by_templatable(Digraph.t(), [module]) ::
          %{module => server_callback_analysis}
  def server_callback_analysis_by_templatable(graph, templatables) do
    templatables
    |> TaskUtils.async_many(fn templatable ->
      analysis = %{
        dispatch_types: server_protocol_dispatch_types(graph, [templatable]),
        reflection_mfas: list_reflection_mfas_reachable_from_server_init(templatable, graph)
      }

      {templatable, analysis}
    end)
    |> Task.await_many(:infinity)
    |> Map.new()
  end

  @doc """
  Returns the set of types that can appear at protocol dispatch in server-executed
  code of the given templatable modules, i.e. code reachable from their init/3 and
  command/3 functions.
  Protocol function vertices are opaque during the traversal, so consolidated
  dispatch edges don't make every loaded implementation's type count as reachable.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/call_graph/server_protocol_dispatch_types_2/README.md
  """
  @spec server_protocol_dispatch_types(Digraph.t(), [module]) :: MapSet.t(module)
  def server_protocol_dispatch_types(graph, templatables) do
    entry_mfas =
      for templatable <- templatables, function <- [:command, :init] do
        {templatable, function, 3}
      end

    graph
    |> Digraph.reachable(entry_mfas, opaque_vertex?: &protocol_function_mfa?/1)
    |> protocol_dispatch_types()
  end

  @doc """
  Returns sorted call graph edges.
  """
  @spec sorted_edges(t) :: [edge]
  def sorted_edges(%{pid: pid}) do
    Agent.get(pid, &Digraph.sorted_edges/1, :infinity)
  end

  @doc """
  Returns sorted call graph vertices.
  """
  @spec sorted_vertices(t) :: [vertex]
  def sorted_vertices(%{pid: pid}) do
    Agent.get(pid, &Digraph.sorted_vertices/1, :infinity)
  end

  @doc """
  Starts a new call graph agent.

  ## Options

    * `:graph` - the initial `Digraph` to seed the agent with; defaults to an empty graph.
    * `:supervisor` - a `DynamicSupervisor` to start the agent under as a `:temporary` child;
      when omitted the agent is linked to the calling process.
  """
  @spec start(T.opts()) :: t
  def start(opts \\ []) do
    graph = opts[:graph] || Digraph.new()

    {:ok, pid} =
      case opts[:supervisor] do
        nil ->
          Agent.start_link(fn -> graph end)

        sup ->
          child_spec = %{
            id: :call_graph,
            restart: :temporary,
            start: {Agent, :start_link, [fn -> graph end]}
          }

          DynamicSupervisor.start_child(sup, child_spec)
      end

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
  Lists MFAs that are reachable from the given call graph vertices.
  The traversal follows every edge, including consolidated protocol dispatch edges,
  so all loaded implementations of a reached protocol are included, regardless of
  whether their target types can occur.
  Unimplemented protocol implementations are excluded.
  These are the semantics for app-agnostic analyses, where no concrete app context
  bounds the types that can occur at protocol dispatch, so any implementation could
  be exercised. For computing what ships to the client for a concrete app, see
  reachable_mfas/3.
  """
  @spec unbounded_reachable_mfas(Digraph.t(), [vertex]) :: [mfa]
  def unbounded_reachable_mfas(graph, vertices) do
    graph
    |> Digraph.reachable(vertices)
    |> Enum.filter(fn
      # Some protocol implementations are referenced but not actually implemented, e.g. Collectable.Atom
      {module, _function, _arity} -> Reflection.module?(module)
      _module_vertex -> false
    end)
  end

  @doc """
  Returns call graph vertices.
  """
  @spec vertices(t) :: [vertex]
  def vertices(%{pid: pid}) do
    Agent.get(pid, &Digraph.vertices/1, :infinity)
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
  defp add_reflection_mfas_reachable_from_server_inits(
         page_mfas,
         page_module,
         server_callback_analysis_by_templatable
       ) do
    templatables = [page_module | extract_uniq_components(page_mfas)]

    added_mfas =
      Enum.flat_map(templatables, fn templatable ->
        server_callback_analysis_by_templatable[templatable].reflection_mfas
      end)

    page_mfas ++ added_mfas
  end

  # Runs protocol-aware reachability rounds until no new implementations become
  # reachable. Each round traverses only vertices not yet in the state, extends the
  # dispatch types only from the newly reached vertices, and evaluates only the new
  # implementation candidates plus the pending ones against the grown type set.
  defp expand_reachable_state(graph, state, entry_vertices) do
    new_vertices =
      Digraph.reachable(graph, entry_vertices,
        opaque_vertex?: &protocol_function_mfa?/1,
        visited_vertices: state.reached_vertices
      )

    reached_vertices = MapSet.union(state.reached_vertices, MapSet.new(new_vertices))
    types = put_protocol_dispatch_types(state.types, new_vertices)

    pending_impl_candidates =
      extract_impl_candidates(graph, new_vertices) ++ state.pending_impl_candidates

    new_state = %{
      state
      | reached_vertices: reached_vertices,
        types: types,
        pending_impl_candidates: pending_impl_candidates
    }

    promote_pending_impl_candidates(graph, new_state)
  end

  # Resumes the fixpoint from the given state with additional dispatch types,
  # reaching exactly the vertices a from-scratch run with those types would reach.
  defp expand_reachable_state_with_types(graph, state, extra_types) do
    new_state = %{state | types: MapSet.union(state.types, extra_types)}
    promote_pending_impl_candidates(graph, new_state)
  end

  # Implementation candidates are read from the dispatch edges added at build time
  # (and refreshed on patch), which is much cheaper than listing implementations
  # via reflection, since that scans BEAM files on disk.
  defp extract_impl_candidates(graph, vertices) do
    for {_protocol, function, arity} = vertex <- vertices,
        protocol_function_mfa?(vertex),
        {_source_vertex, {impl, :__impl__, 1}} <- Digraph.outgoing_edges(graph, vertex),
        impl_entry_vertices =
          Enum.filter(
            [{impl, :__impl__, 1}, {impl, function, arity}],
            &Digraph.has_vertex?(graph, &1)
          ),
        impl_entry_vertices != [] do
      {impl, impl_entry_vertices}
    end
  end

  defp extract_uniq_components(mfas) do
    mfas
    |> Enum.map(fn {module, _function, _arity} -> module end)
    |> Enum.uniq()
    |> Enum.filter(&Reflection.component?/1)
  end

  defp finalize_reachable_mfas(graph, state) do
    reached_vertices = MapSet.to_list(state.reached_vertices)
    helper_vertices = protocol_dispatch_dependency_vertices(graph, reached_vertices)

    vertices = Enum.uniq(reached_vertices ++ helper_vertices)

    Enum.filter(vertices, fn
      # Some protocol implementations are referenced but not actually implemented, e.g. Collectable.Atom
      {module, _function, _arity} -> Reflection.module?(module)
      _module_vertex -> false
    end)
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

  defp maybe_put_struct_type(types, module) do
    if Reflection.has_struct?(module) do
      MapSet.put(types, module)
    else
      types
    end
  end

  # Moves pending implementation candidates whose target type has become reachable
  # into the traversal, continuing rounds until none are promotable.
  defp promote_pending_impl_candidates(graph, state) do
    {ready_candidates, pending_impl_candidates} =
      Enum.split_with(state.pending_impl_candidates, fn {impl, _impl_entry_vertices} ->
        protocol_implementation_reachable?(impl, state.types)
      end)

    impl_entry_vertices =
      ready_candidates
      |> Enum.flat_map(fn {_impl, impl_entry_vertices} -> impl_entry_vertices end)
      |> Enum.reject(&MapSet.member?(state.reached_vertices, &1))
      |> Enum.uniq()

    new_state = %{state | pending_impl_candidates: pending_impl_candidates}

    if impl_entry_vertices == [] do
      new_state
    else
      expand_reachable_state(graph, new_state, impl_entry_vertices)
    end
  end

  defp protocol_dispatch_helper_mfa?(
         {protocol, _function, _arity},
         {protocol, _helper_function, _helper_arity} = target_vertex
       ) do
    !protocol_function_mfa?(target_vertex)
  end

  defp protocol_dispatch_helper_mfa?(_vertex, _target_vertex), do: false

  defp protocol_function_mfa?({module, function, arity}) do
    Reflection.protocol?(module) && {function, arity} in module.__protocol__(:functions)
  end

  defp protocol_function_mfa?(_vertex), do: false

  defp protocol_implementation_reachable?(impl, types) do
    Reflection.protocol_implementation?(impl) && MapSet.member?(types, impl.__impl__(:for))
  end

  # Bodies of functions generated by defprotocol (__protocol__/1, impl_for/1, impl_for!/1,
  # struct_impl_for/1) and defimpl (__impl__/1) enumerate module atoms (implementation
  # modules, dispatch target types, the protocol itself) that are metadata, not dependencies.
  defp protocol_metadata_mfa?({module, function, 1})
       when function in [:__protocol__, :impl_for, :impl_for!, :struct_impl_for] do
    Reflection.protocol?(module)
  end

  defp protocol_metadata_mfa?({module, :__impl__, 1}) do
    Reflection.protocol_implementation?(module)
  end

  defp protocol_metadata_mfa?(_vertex), do: false

  defp put_protocol_dispatch_types(types, vertices) do
    Enum.reduce(vertices, types, fn
      module, acc when is_atom(module) ->
        maybe_put_struct_type(acc, module)

      {module, :__struct__, arity}, acc when arity in [0, 1] ->
        MapSet.put(acc, module)

      _vertex, acc ->
        acc
    end)
  end

  # When modules that are protocol implementations are added or edited, the protocol
  # module itself (e.g. Enumerable) is unchanged and not re-processed by patch. Its
  # dispatch edges remain stale. This function re-runs add_protocol_call_graph_edges
  # for each affected protocol so dispatch edges reflect the current set of implementations.
  # Removed modules are excluded because add_protocol_call_graph_edges auto-creates vertices,
  # which would re-introduce vertices that remove_module_vertices already cleaned up.
  defp refresh_protocol_dispatch_edges(call_graph, added_or_edited_modules) do
    added_or_edited_modules
    |> Enum.map(&Reflection.protocol_implementation/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.each(&add_protocol_call_graph_edges(call_graph, &1))
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

  defp remove_module_vertices(call_graph, module) do
    remove_vertices(call_graph, module_vertices(call_graph, module))
  end

  # Runs the protocol-aware fixpoint from the given entry vertices and returns the
  # resulting state: the reached vertex set, the accumulated dispatch types, and the
  # implementation candidates whose target types are not reachable yet.
  defp start_reachable_state(graph, entry_vertices, extra_types) do
    initial_types =
      @built_in_protocol_types
      |> MapSet.new()
      |> MapSet.union(extra_types)

    state = %{
      reached_vertices: MapSet.new(),
      types: initial_types,
      pending_impl_candidates: []
    }

    expand_reachable_state(graph, state, entry_vertices)
  end
end
