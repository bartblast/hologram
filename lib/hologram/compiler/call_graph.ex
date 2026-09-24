defmodule Hologram.Compiler.CallGraph do
  @moduledoc false

  alias Hologram.Commons.FileUtils
  alias Hologram.Commons.PLT
  alias Hologram.Commons.SerializationUtils
  alias Hologram.Commons.TaskUtils
  alias Hologram.Commons.Types, as: T
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Digraph
  alias Hologram.Compiler.IR
  alias Hologram.Compiler.ReflectionGate
  alias Hologram.Compiler.ReflectionSites
  alias Hologram.Reflection

  # The agent holds the graph, the modules whose definitions were built into it (see modules/1), and
  # what the walk that grows it reached (see build_reach/3).
  defstruct pid: nil, module_info_plt: nil

  @type t :: %CallGraph{pid: pid, module_info_plt: PLT.t() | nil}

  @type broadcast_caller_analysis :: %{
          dispatch_types: MapSet.t(module),
          referenced_components: [module]
        }

  @type edge :: {vertex, vertex}

  # A call of a reflection function on a module the code does not name, found in a function's
  # definition (see Hologram.Compiler.ReflectionSites): a vertex the function has an edge to, so
  # that a walk reaching the function reaches the call.
  @type reflection_site :: {:reflection_site, mfa, atom, arity, ReflectionSites.kind()}

  # What the walk of build_reach/3 reached: the state expand_reachable_state/4 works on, and the
  # templatables whose client entries and server callbacks it walked.
  @type reach :: %{
          pending_impl_candidates: [{module, [vertex]}],
          reached_vertices: MapSet.t(vertex),
          templatables: MapSet.t(module),
          types: MapSet.t(module)
        }

  # What the runtime's own reflection calls open for every page (see runtime_reflection/2).
  @type runtime_reflection :: %{open: MapSet.t({atom, arity})}

  @type server_callback_analysis :: %{
          dispatch_types: MapSet.t(module),
          server_referenced_components: [module]
        }

  @type vertex :: module | mfa | reflection_site

  # A literal empty `MapSet.new()` in the initial state reads as concrete and won't unify
  # with the opaque `MapSet.t()` inferred for the state fields.
  @dialyzer {:no_opaque, [{:empty_reach, 0}, {:start_reachable_state, 4}]}

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

  # The version of what dump/2 writes. A dump of another version is not loaded (see load/2), and the
  # compile starts cold: the compile task then loads neither the module info dump nor the compile
  # state written with the graph. A dump written before the version existed holds a bare graph,
  # which counts as version 0.
  #
  # WARNING: bump it with every change that makes a compile read back something the current code
  # would not write. That is not only a change in the structure of what dump/2 writes (a key added to
  # or removed from the state, a value of another kind), but also a change in what the code puts in
  # it: what build/3 adds to the graph for a module (a new kind of vertex or edge, an edge no longer
  # added) or what Hologram.Reflection.beam_info/1 records about a module. A kept dump holds the
  # graph and the module infos of every module whose beam did not change, as the Hologram that wrote
  # it built them, so without a bump an upgrade keeps them as they were, and the pages built from
  # them can miss functions without any error. One bump per release is enough: if the value already
  # differs from the one at the last release tag, leave it
  # (`git show <tag>:lib/hologram/compiler/call_graph.ex | grep "@dump_version"`, nothing printed
  # meaning 0).
  @dump_version 1

  # Edges for dynamic dispatch: the caller reads the callee module from data
  # (e.g. a struct's calendar field), so static IR analysis can't see the
  # target. Each edge points at the known implementation.
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

  # Each group names the client-runtime mechanism that needs its edges.
  # They can't be discovered from static IR analysis, because the target
  # module is read from data planted by manually ported JavaScript code -
  # e.g. the error_info entry that maps.mjs raise sites put on the raising
  # stacktrace frame, which ErlangError.normalize/2 applies at format time.
  # Deps annotations can't carry these either: the raise sites reference the
  # format module only as data, and the format function name is implicit
  # (the :format_error default), so the MFA is not visible in the JS code.
  # Exception.blame/3 dispatches the same way, on the module of the exception
  # struct it is given.
  @edges_used_by_client_runtime [
    error_message_derivation: [
      {{ErlangError, :normalize, 2}, {:erl_erts_errors, :format_bs_fail, 2}},
      {{ErlangError, :normalize, 2}, {:erl_erts_errors, :format_error, 2}},
      {{ErlangError, :normalize, 2}, {:erl_kernel_errors, :format_error, 2}},
      {{ErlangError, :normalize, 2}, {:erl_stdlib_errors, :format_error, 2}},
      {{Exception, :blame, 3}, {ArithmeticError, :blame, 2}}
    ]
  ]

  # TODO: Determine automatically based on deps annotations next to function implementations
  @erlang_mfa_edges [
    {{:binary, :compile_pattern, 1}, {:erlang, :make_ref, 0}},
    {{:binary, :match, 2}, {:binary, :match, 3}},
    {{:binary, :match, 3}, {:binary, :_aho_corasick_search, 3}},
    {{:binary, :match, 3}, {:binary, :_boyer_moore_search, 4}},
    {{:binary, :match, 3}, {:binary, :_parse_search_opts, 1}},
    {{:binary, :match, 3}, {:binary, :compile_pattern, 1}},
    {{:binary, :matches, 2}, {:binary, :matches, 3}},
    {{:binary, :matches, 3}, {:binary, :_parse_search_opts, 1}},
    {{:binary, :matches, 3}, {:binary, :compile_pattern, 1}},
    {{:binary, :matches, 3}, {:binary, :match, 3}},
    {{:binary, :replace, 3}, {:binary, :replace, 4}},
    {{:binary, :replace, 4}, {:binary, :compile_pattern, 1}},
    {{:binary, :replace, 4}, {:binary, :match, 3}},
    {{:binary, :replace, 4}, {:binary, :split, 3}},
    {{:binary, :replace, 4}, {:erlang, :iolist_to_binary, 1}},
    {{:binary, :split, 2}, {:binary, :split, 3}},
    {{:binary, :split, 3}, {:binary, :_is_valid_pattern, 1}},
    {{:binary, :split, 3}, {:binary, :_parse_search_opts, 1}},
    {{:binary, :split, 3}, {:binary, :compile_pattern, 1}},
    {{:binary, :split, 3}, {:binary, :match, 3}},
    {{:elixir_aliases, :safe_concat, 1}, {:elixir_aliases, :concat, 1}},
    {{:elixir_locals, :yank, 2}, {:maps, :remove, 2}},
    {{:elixir_utils, :jaro_similarity, 2}, {:unicode_util, :cp, 1}},
    {{:erl_erts_errors, :_format_erlang_error, 3}, {:erlang, :_is_valid_time_unit, 1}},
    {{:erl_erts_errors, :_format_error_map, 3}, {:erl_erts_errors, :_expand_error, 1}},
    {{:erl_erts_errors, :format_error, 2}, {:erl_erts_errors, :_format_erlang_error, 3}},
    {{:erl_erts_errors, :format_error, 2}, {:erl_erts_errors, :_format_error_map, 3}},
    {{:erl_kernel_errors, :_format_error_map, 3}, {:erl_kernel_errors, :_expand_error, 1}},
    {{:erl_kernel_errors, :format_error, 2}, {:erl_kernel_errors, :_format_error_map, 3}},
    {{:erl_kernel_errors, :format_error, 2}, {:erl_kernel_errors, :_format_os_error, 3}},
    {{:erl_stdlib_errors, :_format_binary_error, 3}, {:erl_stdlib_errors, :_must_be_binary, 1}},
    {{:erl_stdlib_errors, :_format_binary_error, 3},
     {:erl_stdlib_errors, :_must_be_binary_replacement, 1}},
    {{:erl_stdlib_errors, :_format_binary_error, 3},
     {:erl_stdlib_errors, :_must_be_non_neg_integer, 1}},
    {{:erl_stdlib_errors, :_format_binary_error, 3}, {:erl_stdlib_errors, :_must_be_pattern, 1}},
    {{:erl_stdlib_errors, :_format_binary_error, 3}, {:erl_stdlib_errors, :_must_be_position, 1}},
    {{:erl_stdlib_errors, :_format_error_map, 3}, {:erl_stdlib_errors, :_expand_error, 1}},
    {{:erl_stdlib_errors, :_format_lists_error, 2}, {:erl_stdlib_errors, :_must_be_list, 1}},
    {{:erl_stdlib_errors, :_format_maps_error, 2}, {:erl_stdlib_errors, :_must_be_fun, 2}},
    {{:erl_stdlib_errors, :_format_maps_error, 2}, {:erl_stdlib_errors, :_must_be_list, 1}},
    {{:erl_stdlib_errors, :_format_maps_error, 2}, {:erl_stdlib_errors, :_must_be_map, 1}},
    {{:erl_stdlib_errors, :_format_maps_error, 2},
     {:erl_stdlib_errors, :_must_be_map_or_iter, 1}},
    {{:erl_stdlib_errors, :_format_math_error, 2}, {:erl_stdlib_errors, :_must_be_number, 1}},
    {{:erl_stdlib_errors, :_format_re_error, 3}, {:erl_stdlib_errors, :_must_be_iodata, 1}},
    {{:erl_stdlib_errors, :_format_re_error, 3}, {:erl_stdlib_errors, :_must_be_regexp, 1}},
    {{:erl_stdlib_errors, :_format_re_error, 3}, {:erl_stdlib_errors, :_re_compile_error, 1}},
    {{:erl_stdlib_errors, :_format_unicode_error, 2},
     {:erl_stdlib_errors, :_unicode_char_data, 1}},
    {{:erl_stdlib_errors, :_format_unicode_error, 2},
     {:erl_stdlib_errors, :_unicode_encoding, 1}},
    {{:erl_stdlib_errors, :_must_be_iodata, 1}, {:erl_stdlib_errors, :_is_iodata, 1}},
    {{:erl_stdlib_errors, :_must_be_map_or_iter, 1}, {:maps, :is_iterator_valid, 1}},
    {{:erl_stdlib_errors, :_must_be_pattern, 1}, {:binary, :_is_valid_pattern, 1}},
    {{:erl_stdlib_errors, :_must_be_regexp, 1}, {:erl_stdlib_errors, :_re_compile_error, 1}},
    {{:erl_stdlib_errors, :_re_compile_error, 1}, {:erl_stdlib_errors, :_is_iodata, 1}},
    {{:erl_stdlib_errors, :_re_compile_error, 1}, {:erlang, :iolist_to_binary, 1}},
    {{:erl_stdlib_errors, :_unicode_char_data, 1}, {:unicode, :_chardata_to_utf8_binary, 1}},
    {{:erl_stdlib_errors, :format_error, 2}, {:erl_stdlib_errors, :_format_binary_error, 3}},
    {{:erl_stdlib_errors, :format_error, 2}, {:erl_stdlib_errors, :_format_error_map, 3}},
    {{:erl_stdlib_errors, :format_error, 2}, {:erl_stdlib_errors, :_format_lists_error, 2}},
    {{:erl_stdlib_errors, :format_error, 2}, {:erl_stdlib_errors, :_format_maps_error, 2}},
    {{:erl_stdlib_errors, :format_error, 2}, {:erl_stdlib_errors, :_format_math_error, 2}},
    {{:erl_stdlib_errors, :format_error, 2}, {:erl_stdlib_errors, :_format_re_error, 3}},
    {{:erl_stdlib_errors, :format_error, 2}, {:erl_stdlib_errors, :_format_unicode_error, 2}},
    {{:erlang, :"=<", 2}, {:erlang, :<, 2}},
    {{:erlang, :"=<", 2}, {:erlang, :==, 2}},
    {{:erlang, :>=, 2}, {:erlang, :==, 2}},
    {{:erlang, :>=, 2}, {:erlang, :>, 2}},
    {{:erlang, :atom_to_binary, 1}, {:erlang, :atom_to_binary, 2}},
    {{:erlang, :binary_to_atom, 1}, {:erlang, :binary_to_atom, 2}},
    {{:erlang, :binary_to_existing_atom, 1}, {:erlang, :binary_to_atom, 1}},
    {{:erlang, :binary_to_existing_atom, 2}, {:erlang, :binary_to_atom, 2}},
    {{:erlang, :binary_to_integer, 1}, {:erlang, :binary_to_integer, 2}},
    {{:erlang, :convert_time_unit, 3}, {:erlang, :_is_valid_time_unit, 1}},
    {{:erlang, :error, 1}, {:erlang, :error, 3}},
    {{:erlang, :error, 2}, {:erlang, :error, 3}},
    {{:erlang, :float_to_list, 2}, {:erlang, :float_to_binary, 2}},
    {{:erlang, :fun_info, 2}, {:erlang, :fun_info, 1}},
    {{:erlang, :integer_to_binary, 1}, {:erlang, :integer_to_binary, 2}},
    {{:erlang, :integer_to_list, 1}, {:erlang, :integer_to_list, 2}},
    {{:erlang, :iolist_to_binary, 1}, {:erlang, :list_to_binary, 1}},
    {{:erlang, :is_map_key, 2}, {:maps, :is_key, 2}},
    {{:erlang, :list_to_existing_atom, 1}, {:erlang, :list_to_atom, 1}},
    {{:erlang, :list_to_integer, 1}, {:erlang, :list_to_integer, 2}},
    {{:erlang, :map_get, 2}, {:maps, :get, 2}},
    {{:erlang, :monotonic_time, 1}, {:erlang, :_is_valid_time_unit, 1}},
    {{:erlang, :monotonic_time, 1}, {:erlang, :convert_time_unit, 3}},
    {{:erlang, :monotonic_time, 1}, {:erlang, :monotonic_time, 0}},
    {{:erlang, :split_binary, 2}, {:erlang, :byte_size, 1}},
    {{:erlang, :system_time, 0}, {:os, :system_time, 0}},
    {{:erlang, :system_time, 1}, {:os, :system_time, 1}},
    {{:erlang, :time_offset, 0}, {:erlang, :monotonic_time, 0}},
    {{:erlang, :time_offset, 0}, {:os, :system_time, 0}},
    {{:erlang, :time_offset, 1}, {:erlang, :_is_valid_time_unit, 1}},
    {{:erlang, :time_offset, 1}, {:erlang, :convert_time_unit, 3}},
    {{:erlang, :time_offset, 1}, {:erlang, :time_offset, 0}},
    {{:erlang, :unique_integer, 1}, {:erlang, :unique_integer, 0}},
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
    {{:lists, :filter, 2}, {:erlang, :error, 1}},
    {{:lists, :flatten, 1}, {:lists, :_do_flatten, 2}},
    {{:lists, :flatten, 2}, {:lists, :_do_flatten, 2}},
    {{:lists, :keymember, 3}, {:lists, :keyfind, 3}},
    {{:lists, :keysort, 2}, {:erlang, :element, 2}},
    {{:lists, :seq, 2}, {:lists, :seq, 3}},
    {{:maps, :take, 2}, {:maps, :get, 3}},
    {{:maps, :take, 2}, {:maps, :remove, 2}},
    {{:maps, :update, 3}, {:maps, :is_key, 2}},
    {{:maps, :update, 3}, {:maps, :put, 3}},
    {{:os, :system_time, 1}, {:erlang, :_is_valid_time_unit, 1}},
    {{:os, :system_time, 1}, {:erlang, :convert_time_unit, 3}},
    {{:os, :system_time, 1}, {:os, :system_time, 0}},
    {{:re, :compile, 1}, {:re, :compile, 2}},
    {{:re, :compile, 2}, {:erlang, :iolist_to_binary, 1}},
    {{:re, :compile, 2}, {:erlang, :make_ref, 0}},
    {{:re, :import, 1}, {:re, :compile, 2}},
    {{:re, :run, 2}, {:re, :run, 3}},
    {{:re, :run, 3}, {:erlang, :iolist_to_binary, 1}},
    {{:sets, :_validate_opts, 1}, {:lists, :keyfind, 3}},
    {{:sets, :add_element, 2}, {:maps, :put, 3}},
    {{:sets, :del_element, 2}, {:maps, :remove, 2}},
    {{:sets, :filter, 2}, {:erlang, :error, 1}},
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
    {{:string, :join, 2}, {:erlang, :error, 1}},
    {{:string, :length, 1}, {:erlang, :error, 1}},
    {{:string, :length, 1}, {:unicode, :characters_to_binary, 1}},
    {{:string, :length, 1}, {:unicode_util, :gc, 1}},
    {{:string, :replace, 3}, {:string, :replace, 4}},
    {{:string, :replace, 4}, {:unicode, :characters_to_binary, 1}},
    {{:string, :split, 2}, {:string, :split, 3}},
    {{:string, :split, 3}, {:unicode, :characters_to_binary, 1}},
    {{:string, :titlecase, 1}, {:erlang, :error, 1}},
    {{:string, :titlecase, 1}, {:unicode_util, :cp, 1}},
    {{:string, :to_graphemes, 1}, {:erlang, :error, 1}},
    {{:string, :to_graphemes, 1}, {:unicode_util, :gc, 1}},
    {{:unicode, :_chardata_to_utf8_binary, 1}, {:unicode, :_flatten_chardata, 1}},
    {{:unicode, :characters_to_binary, 1}, {:unicode, :_chardata_to_utf8_binary, 1}},
    {{:unicode, :characters_to_binary, 1}, {:unicode, :characters_to_list, 1}},
    {{:unicode, :characters_to_binary, 3}, {:unicode, :_chardata_to_utf8_binary, 1}},
    {{:unicode, :characters_to_binary, 3}, {:unicode, :characters_to_list, 1}},
    {{:unicode, :characters_to_list, 1}, {:unicode, :_flatten_chardata, 1}},
    {{:unicode, :characters_to_nfc_binary, 1}, {:unicode, :_chardata_to_utf8_binary, 1}},
    {{:unicode, :characters_to_nfc_list, 1}, {:unicode, :characters_to_nfc_binary, 1}},
    {{:unicode, :characters_to_nfc_list, 1}, {:unicode, :_flatten_chardata, 1}},
    {{:unicode, :characters_to_nfd_binary, 1}, {:unicode, :_chardata_to_utf8_binary, 1}},
    {{:unicode, :characters_to_nfkc_binary, 1}, {:unicode, :_chardata_to_utf8_binary, 1}},
    {{:unicode, :characters_to_nfkd_binary, 1}, {:unicode, :_chardata_to_utf8_binary, 1}},
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
    {{:unicode_util, :gc, 1}, {:unicode_util, :cp, 1}},
    {{:uri_string, :parse, 1}, {:unicode, :characters_to_binary, 1}}
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
    {Code, :ensure_compiled, 1},
    {Code, :ensure_loaded, 1},
    {Exception, :format_stacktrace, 1},
    {FunctionClauseError, :message, 1},
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
    {String.Tokenizer, :tokenize, 1},
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
      {Exception, :blame, 3},
      {Exception, :message, 1},
      {Exception, :normalize, 3},
      {Macro, :inspect_atom, 3},
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
    manually_ported_function_clause_error_module: [
      {Exception, :format_mfa, 3}
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
      # The renderer raises this by name - Interpreter.raiseError takes the alias as a string, so no
      # module atom appears in client-reachable code for the compiler to follow. Without this the
      # struct reaches the client but its module doesn't, and deriving the message fails with
      # UndefinedFunctionError instead of naming the prop that broke its contract.
      {Hologram.PropError, :message, 1},
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

  # MFAs called by the JavaScript that Encoder emits for encoded terms.
  @mfas_used_by_encoded_terms [
    # Encoded Regex terms rebuild their compiled patterns on evaluation.
    {:re, :import, 1}
  ]

  # The module flags under which build/3 gives a module's own vertex edges (to its template, its
  # struct functions and the like); a module's body holds nothing else that adds edges from its
  # vertex. A module named only as a value, whose vertex the walk of build_reach/3 reaches, is built
  # when it has one of them: otherwise building it would add no edge to that vertex.
  @module_vertex_edge_flags [:component?, :ecto_schema?, :exception?, :page?, :struct?]

  @doc """
  Adds an edge between two vertices in the call graph.
  Automatically adds vertices if they don't exist.
  """
  @spec add_edge(t, vertex, vertex) :: t
  def add_edge(%{pid: pid} = call_graph, from_vertex, to_vertex) do
    update_graph(pid, &Digraph.add_edge(&1, from_vertex, to_vertex))
    call_graph
  end

  @doc """
  Adds multiple edges to the call graph.
  Automatically adds vertices if they don't exist.
  """
  @spec add_edges(t, [edge]) :: t
  def add_edges(%{pid: pid} = call_graph, edges) do
    update_graph(pid, &Digraph.add_edges(&1, edges))
    call_graph
  end

  @doc """
  Adds call graph edges that can't be discovered from static IR analysis:
  Erlang functions depending on other Erlang functions, dynamic dispatch
  where the callee module is read from data (e.g. a struct's calendar field),
  and edges needed by client-runtime mechanisms (e.g. error message derivation).
  """
  @spec add_non_discoverable_edges(t) :: t
  def add_non_discoverable_edges(%{pid: pid} = call_graph) do
    client_runtime_edges =
      Enum.flat_map(@edges_used_by_client_runtime, fn {_mechanism, edges} -> edges end)

    update_graph(pid, fn graph ->
      graph
      |> Digraph.add_edges(client_runtime_edges)
      |> Digraph.add_edges(@dynamic_dispatch_edges)
      |> Digraph.add_edges(@erlang_mfa_edges)
    end)

    call_graph
  end

  @doc """
  Adds the vertex to the call graph.
  """
  @spec add_vertex(t, vertex) :: t
  def add_vertex(%{pid: pid} = call_graph, vertex) do
    update_graph(pid, &Digraph.add_vertex(&1, vertex))
    call_graph
  end

  @doc """
  Returns the set of types that can appear at protocol dispatch anywhere in an
  app with the given pages: types reachable from the client code of the pages,
  types created in server-executed code of the pages, their components, and the
  broadcast-referenced components, and types reachable from action broadcasting
  code (taken from the given precomputed broadcast caller analysis).
  """
  @spec app_protocol_dispatch_types(
          Digraph.t(),
          [module],
          broadcast_caller_analysis,
          PLT.t() | nil
        ) :: MapSet.t(module)
  def app_protocol_dispatch_types(graph, pages, broadcast_caller_analysis, module_info_plt) do
    page_entry_mfas = Enum.flat_map(pages, &list_page_entry_mfas(&1, module_info_plt))

    page_vertices =
      Digraph.reachable(graph, page_entry_mfas,
        opaque_vertex?: &protocol_function_mfa?(&1, module_info_plt)
      )

    components =
      page_vertices
      |> Enum.filter(&match?({_module, _function, _arity}, &1))
      |> extract_uniq_components(module_info_plt)

    # A broadcast-referenced component executes its server callbacks like any other
    # rendered component (e.g. command/3 triggered while it is mounted), so its
    # server-created types count as app types.
    templatables =
      Enum.uniq(pages ++ components ++ broadcast_caller_analysis.referenced_components)

    client_types = protocol_dispatch_types(page_vertices, module_info_plt)
    server_types = server_protocol_dispatch_types(graph, templatables, module_info_plt)

    client_types
    |> MapSet.union(server_types)
    |> MapSet.union(broadcast_caller_analysis.dispatch_types)
  end

  @doc """
  Returns the analysis of code reachable from the callers of the functions that
  broadcast actions: Hologram.Component.put_broadcast/3,4,
  put_broadcast_except/4,5 and Hologram.Realtime.broadcast_action/2,3,
  broadcast_action_except/3,4. Returns the protocol dispatch types that can
  appear in that code and the component modules referenced in it. A broadcast
  can deliver its payload to any connected client, so referenced components must
  be available in the runtime bundle and the types count as app-wide dispatch types.
  Protocol function vertices are opaque during the traversal, so consolidated
  dispatch edges don't make every loaded implementation's type count as reachable.
  """
  @spec broadcast_caller_analysis(Digraph.t(), PLT.t() | nil) :: broadcast_caller_analysis
  def broadcast_caller_analysis(graph, module_info_plt) do
    caller_vertices =
      for broadcast_mfa <- Reflection.broadcast_mfas(),
          {caller_vertex, _broadcast_mfa} <- Digraph.incoming_edges(graph, broadcast_mfa) do
        caller_vertex
      end

    broadcast_vertices =
      Digraph.reachable(graph, caller_vertices,
        opaque_vertex?: &protocol_function_mfa?(&1, module_info_plt)
      )

    %{
      dispatch_types: protocol_dispatch_types(broadcast_vertices, module_info_plt),
      referenced_components:
        extract_component_module_vertices(broadcast_vertices, module_info_plt)
    }
  end

  @doc """
  Builds a call graph from IR.
  """
  # WARNING: a change in what this adds to the graph needs a bump of @dump_version (see the warning
  # there), or a kept graph dump keeps what the previous code added.
  @spec build(t, IR.t() | list | map | tuple, vertex | nil) :: t
  def build(call_graph, ir, from_vertex \\ nil)

  def build(call_graph, %IR.AtomType{value: value}, from_vertex) do
    if Reflection.alias?(value) &&
         !protocol_metadata_mfa?(from_vertex, call_graph.module_info_plt) do
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
    |> add_reflection_site_edges(fun_def_vertex, clause)
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
    |> put_module(module)
    |> maybe_add_templatable_call_graph_edges(module)
    |> maybe_add_protocol_call_graph_edges(module)
    |> maybe_add_struct_call_graph_edges(module)
    |> maybe_add_ecto_schema_call_graph_edges(module)
    |> maybe_add_exception_call_graph_edges(module)
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

  # An :erlang.error/3 raise site with an error_info option makes the runtime
  # call the named format module when deriving the error message, as specified
  # by EEP-54 (Erlang Enhancement Proposal 54, "Provide more information about
  # errors"). That call never appears in the code - it's resolved from the
  # error_info map at runtime. Mirror the resolution here, honoring its
  # defaults (the raising module and :format_error), so the formatter reaches
  # the bundle.
  def build(
        call_graph,
        %IR.RemoteFunctionCall{
          module: %IR.AtomType{value: :erlang},
          function: :error,
          args: [_reason, _args, options] = args
        },
        from_vertex
      ) do
    call_graph
    |> add_edge(from_vertex, {:erlang, :error, 3})
    |> maybe_add_error_info_formatter_edge(options, from_vertex)
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
  Grows the graph until it holds every module the pages, the runtime and the broadcast callers
  reach, and returns the modules it asked to build, in the order asked.

  The walk follows edges with the rules of reachable_mfas/4 (protocol functions opaque, an
  implementation entered once its type is reached), over one type set for the whole app, and adds
  what the listings add: the dispatch helpers of the reached protocol functions, and the module
  vertex and server callbacks of every component it reaches. It runs in rounds: a round walks the
  graph as it is, and the reached functions and module vertices of modules the graph holds no
  definition of, which the module info PLT knows, are what `build_modules` is called with. Those
  are walked again in the next round, with their calls in place. When a round asks for no module,
  the graph holds everything every listing of the compile can reach.

  What the walk reached is kept in the agent, and dumped with the graph, so the walk starts from
  what the given diff (narrowed, see narrow_diff/2, and already patched in) replaced: the reached
  functions of the edited modules, walked again; the entries of the added and edited pages and
  broadcast callers; the reached functions of the protocol of an added or edited implementation,
  whose dispatch edges the patch refreshed; and the runtime entries not reached yet. A removed
  module's reached functions are forgotten. On an empty reach, every page and broadcast caller is
  in the diff as added, which makes it a walk of the whole app.
  """
  @spec build_reach(t, map, ([module] -> any)) :: [module]
  def build_reach(%{pid: pid, module_info_plt: module_info_plt} = call_graph, diff, build_modules) do
    entries =
      Agent.get_and_update(
        pid,
        fn state ->
          {entries, reach} = reach_entries(state, diff, module_info_plt)
          {entries, %{state | reach: reach}}
        end,
        :infinity
      )

    build_reach_rounds(call_graph, entries, build_modules, [])
  end

  @doc """
  Returns a clone of the given call graph, with its modules. The clone starts with nothing reached
  (see build_reach/3): it is a graph to list from, not one to grow.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/call_graph/clone_1/README.md
  """
  @spec clone(t, T.opts()) :: t
  def clone(%{pid: pid} = call_graph, opts \\ []) do
    {graph, modules} = Agent.get(pid, &{&1.graph, &1.modules}, :infinity)

    opts
    |> Keyword.put(:graph, graph)
    |> Keyword.put(:modules, modules)
    |> Keyword.put(:module_info_plt, call_graph.module_info_plt)
    |> start()
  end

  @doc """
  Serializes the call graph, its modules and what the walk of build_reach/3 reached included, and
  writes it to a file, tagged with the dump version that load/2 checks.

  Benchmarks: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/call_graph/dump_2/README.md
  """
  @spec dump(t, String.t()) :: t
  def dump(%{pid: pid} = call_graph, path) do
    state = Agent.get(pid, & &1, :infinity)
    data = SerializationUtils.serialize({@dump_version, state})

    path
    |> Path.dirname()
    |> File.mkdir_p!()

    FileUtils.write_atomically!(path, data)

    call_graph
  end

  @doc """
  Returns graph edges.
  """
  @spec edges(t) :: [edge]
  def edges(%{pid: pid}) do
    read_graph(pid, &Digraph.edges/1)
  end

  @doc """
  Returns the calls between manually ported Erlang functions, which no IR
  analysis can discover, since their bodies are JavaScript.
  """
  @spec erlang_mfa_edges :: [{mfa, mfa}]
  def erlang_mfa_edges, do: @erlang_mfa_edges

  @doc """
  Returns the underlying %Digraph{} struct containing vertices and edges data.
  """
  @spec get_graph(t) :: Digraph.t()
  def get_graph(%{pid: pid}) do
    read_graph(pid, & &1)
  end

  @doc """
  Checks if an edge exists between two given vertices in the call graph.
  """
  @spec has_edge?(t, vertex, vertex) :: boolean
  def has_edge?(%{pid: pid}, from_vertex, to_vertex) do
    read_graph(pid, &Digraph.has_edge?(&1, from_vertex, to_vertex))
  end

  @doc """
  Checks if the given vertex exists in the call graph.
  """
  @spec has_vertex?(t, vertex) :: boolean
  def has_vertex?(%{pid: pid}, vertex) do
    read_graph(pid, &Digraph.has_vertex?(&1, vertex))
  end

  @doc """
  Returns a MapSet of MFAs that transitively call `Task.await/1`.

  Must be called on the original call graph before `remove_manually_ported_mfas/1`
  strips the `Task.await/1` vertex.

  The walk runs inside the call graph's agent, so the graph is not copied out. It cannot raise: it
  is a traversal of the graph, and a raise inside the agent would take the kept graph down with it.
  """
  @spec list_async_mfas(t) :: MapSet.t(mfa)
  def list_async_mfas(call_graph) do
    read_graph(call_graph.pid, &list_async_mfas_in_graph/1)
  end

  @doc """
  Returns the modules of every vertex from which a vertex of the given modules can be reached, the
  given modules included. The compile task uses it, before the graph is patched, to find the pages
  and components a change to those modules can affect: every way a page's bundle depends on a module
  is a path in the graph from a vertex of the page, or of a component it renders, to that module.
  Given no module, it returns the empty set without reading the graph.

  The walk runs inside the call graph's agent, so the graph is not copied out. It cannot raise: it
  is a traversal of the graph and reads of the module info PLT, and a raise inside the agent would
  take the kept graph down with it.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/call_graph/list_modules_reaching_2/README.md
  """
  @spec list_modules_reaching(t, [module]) :: MapSet.t(module)
  # Built from the argument: an empty MapSet literal is inlined, and Dialyzer then rejects the result
  # where a caller passes it on to a MapSet function.
  def list_modules_reaching(_call_graph, [] = modules), do: MapSet.new(modules)

  def list_modules_reaching(call_graph, modules) do
    target_modules = MapSet.new(modules)

    read_graph(
      call_graph.pid,
      &list_modules_reaching_in_graph(&1, target_modules, call_graph.module_info_plt)
    )
  end

  @doc """
  Lists the entry MFAs {module, function, arity} for a given page module.

  This function returns a list of MFAs that are considered entry points for a page,
  including functions from both the page module and its associated layout module.

  ## Parameters

    * `page_module` - The module of the page for which to list entry MFAs.
    * `module_info_plt` - The module info PLT the layout module is read from, or nil to ask the page.

  ## Returns

  A list of MFAs (tuples of {module, function, arity}) that serve as entry points
  for the given page module and its layout.
  """
  @spec list_page_entry_mfas(module, PLT.t() | nil) :: [mfa]
  def list_page_entry_mfas(page_module, module_info_plt) do
    layout_module = layout_module(page_module, module_info_plt)

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
  Server dispatch types and server-referenced components of
  the page's templatables come from their server callback analyses (see
  server_callback_analysis_by_templatable/3), which are read from `analyses`, a PLT the caller keeps
  for as long as it lists pages, and computed and put there when missing. Pages listed against the
  same PLT, at once or in rounds, compute each templatable's analysis once; tasks listing pages at
  once may compute a missing analysis twice and put the same value twice, which is harmless.
  The graph is taken as it is, so that callers running many pages at once
  can share one graph (see with_shared_graph/2) instead of each copying it out of the call graph.

  The reflection functions (`__struct__/0,1` of a struct, `__changeset__/0` and `__schema__/1,2` of
  an Ecto schema) of the types that can appear at protocol dispatch on the page are listed the way
  the protocol implementations of those types are, but only the ones the page can call on a module
  its code does not name: the `:gate` opt (see `Hologram.Compiler.ReflectionGate`) says which,
  from the reflection calls the page's client code reaches and the ones the runtime holds. With no
  gate, every reflection function of every such type is listed.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/call_graph/list_page_mfas_4/README.md
  """
  @spec list_page_mfas(Digraph.t(), module, PLT.t(), PLT.t() | nil, T.opts()) :: [mfa]
  def list_page_mfas(graph, page_module, analyses, module_info_plt, opts \\ []) do
    entry_mfas = list_page_entry_mfas(page_module, module_info_plt)

    initial_state = start_reachable_state(graph, entry_mfas, MapSet.new(), module_info_plt)
    initial_mfas = Enum.filter(initial_state.reached_vertices, &is_tuple/1)
    initial_templatables = [page_module | extract_uniq_components(initial_mfas, module_info_plt)]

    {expanded_state, templatables} =
      expand_reachable_state_with_server_referenced_components(
        graph,
        initial_state,
        initial_templatables,
        analyses,
        module_info_plt
      )

    server_types =
      Enum.reduce(templatables, MapSet.new(), fn templatable, acc ->
        analysis = server_callback_analysis(graph, templatable, analyses, module_info_plt)
        MapSet.union(acc, analysis.dispatch_types)
      end)

    final_state =
      expand_reachable_state_with_types(graph, expanded_state, server_types, module_info_plt)

    open_reflection_functions =
      ReflectionGate.open_functions(graph, final_state.reached_vertices, entry_mfas, opts[:gate])

    graph
    |> finalize_reachable_mfas(final_state, module_info_plt)
    |> reject_hex_mfas()
    |> add_reflection_mfas(final_state.types, open_reflection_functions, module_info_plt)
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
    |> Enum.reduce(@mfas_used_by_all_pages_and_components ++ @mfas_used_by_encoded_terms, fn
      {_key, mfas}, acc -> mfas ++ acc
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Lists MFAs required by the runtime JS script of an app with the given pages,
  including the client MFAs of components referenced in broadcast caller code.

  The walk runs inside the call graph's agent, so the graph is not copied out. It cannot raise: it
  is a traversal of the graph and reads of the module info PLT. The analyses PLT it starts is
  started from the agent and stopped there too, before it returns.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/call_graph/list_runtime_mfas_2/README.md
  """
  @spec list_runtime_mfas(t, [module]) :: [mfa]
  def list_runtime_mfas(call_graph, pages) do
    read_graph(
      call_graph.pid,
      &list_runtime_mfas_in_graph(&1, pages, call_graph.module_info_plt)
    )
  end

  @doc """
  Loads the graph, its modules and its reach from the given dump file and returns :ok, or returns
  :error and leaves the call graph as it is when the dump was written with another dump version (see
  dump/2), such as one written before the version existed.
  """
  @spec load(t, String.t()) :: :ok | :error
  def load(%{pid: pid}, dump_path) do
    case dump_path
         |> File.read!()
         |> SerializationUtils.deserialize(true) do
      {@dump_version, state} ->
        Agent.cast(pid, fn _state -> state end)
        :ok

      _other_version ->
        :error
    end
  end

  @doc """
  Returns the list of Elixir MFAs that are manually ported to JavaScript.
  """
  @spec manually_ported_elixir_mfas :: [mfa]
  def manually_ported_elixir_mfas, do: @manually_ported_elixir_mfas

  @doc """
  Returns the module info PLT the call graph was started with, or nil.
  """
  @spec module_info_plt(t) :: PLT.t() | nil
  def module_info_plt(%CallGraph{module_info_plt: module_info_plt}), do: module_info_plt

  @doc """
  Returns the vertices that belong to the given module (see vertex_module/1): the module's own vertex,
  its MFAs and the reflection sites of its functions.
  """
  @spec module_vertices(t, module) :: [vertex]
  def module_vertices(call_graph, module) do
    call_graph
    |> vertices()
    |> Enum.filter(&(vertex_module(&1) == module))
  end

  @doc """
  Returns the modules whose definitions were built into the graph (see build/3): the graph holds a
  vertex per function of each and their calls as edges. A module named only by a call or an alias
  in another module's function has vertices too, but is not among them.
  """
  @spec modules(t) :: MapSet.t(module)
  def modules(%{pid: pid}) do
    Agent.get(pid, & &1.modules, :infinity)
  end

  @doc """
  Narrows a module digests diff to the modules the graph holds or must come to hold. The graph is
  built for the modules the pages, the runtime and the broadcast callers reach, so an added or edited
  module outside that reach has no vertices to patch and no IR to build. Kept: every removed module;
  an edited module among the graph's modules (see modules/1); an added or edited page or broadcast
  caller, which the walk that grows the graph starts from, since a new page or a module that starts
  broadcasting is reached by nobody else; and an added or edited implementation of a protocol the
  graph holds, so that patch/3 refreshes the protocol's dispatch edges with it whether or not its
  type is reached yet, since implementation candidates are read from those edges.
  """
  @spec narrow_diff(t, %{
          added_modules: [module],
          edited_modules: [module],
          removed_modules: [module]
        }) :: %{added_modules: [module], edited_modules: [module], removed_modules: [module]}
  def narrow_diff(%{module_info_plt: module_info_plt} = call_graph, diff) do
    modules = modules(call_graph)

    graph_module? = fn module ->
      MapSet.member?(modules, module) or flag?(module_info_plt, module, :page?) or
        flag?(module_info_plt, module, :broadcast_caller?) or
        implementation_of_graph_protocol?(module, modules, module_info_plt)
    end

    %{
      diff
      | added_modules: Enum.filter(diff.added_modules, graph_module?),
        edited_modules: Enum.filter(diff.edited_modules, graph_module?)
    }
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
    TaskUtils.map_concurrently(diff.removed_modules, &remove_module_vertices(call_graph, &1))

    TaskUtils.map_concurrently(diff.edited_modules, fn module ->
      remote_incoming_edges = remote_incoming_edges(call_graph, module)

      call_graph
      |> remove_module_vertices(module)
      |> build_for_module(ir_plt, module)
      |> add_edges(remote_incoming_edges)
    end)

    TaskUtils.map_concurrently(diff.added_modules, &build_for_module(call_graph, ir_plt, &1))

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
  @spec protocol_dispatch_dependency_vertices(Digraph.t(), [vertex], PLT.t() | nil) :: [vertex]
  def protocol_dispatch_dependency_vertices(graph, vertices, module_info_plt) do
    helper_entry_vertices =
      protocol_dispatch_helper_entry_vertices(graph, vertices, module_info_plt)

    Digraph.reachable(graph, helper_entry_vertices,
      opaque_vertex?: &protocol_function_mfa?(&1, module_info_plt)
    )
  end

  # TODO: include types declared via the client-side MFA whitelisting feature once it exists.
  @doc """
  Returns the set of types that can appear at protocol dispatch in the code
  represented by the given call graph vertices.
  The set includes the built-in protocol dispatch types, the struct modules among
  module vertices, and the modules of __struct__/0 and __struct__/1 MFAs.
  """
  @spec protocol_dispatch_types([vertex], PLT.t() | nil) :: MapSet.t(module)
  def protocol_dispatch_types(vertices, module_info_plt) do
    @built_in_protocol_types
    |> MapSet.new()
    |> put_protocol_dispatch_types(vertices, module_info_plt)
  end

  @doc """
  Replaces the graph of the underlying Agent process with the given graph, keeping the modules.
  """
  @spec put_graph(t, Digraph.t()) :: t
  def put_graph(%{pid: pid} = call_graph, graph) do
    update_graph(pid, fn _graph -> graph end)
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
  @spec reachable_mfas(Digraph.t(), [vertex], MapSet.t(module), PLT.t() | nil) :: [mfa]
  def reachable_mfas(graph, entry_vertices, extra_types, module_info_plt) do
    state = start_reachable_state(graph, entry_vertices, extra_types, module_info_plt)
    finalize_reachable_mfas(graph, state, module_info_plt)
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

  The graph's vertex and edge maps are filtered in one pass each. remove_vertices/2 cleans up the
  neighbours of each removed vertex one by one, and the runtime MFAs of a large app are thousands
  of functions called from all over the graph, so it touches the graph many times over: on a graph
  of 160,893 vertices and 613,932 edges with 2,812 runtime MFAs it took 8.8 s, against 0.31 s here.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/call_graph/remove_runtime_mfas!_2/README.md
  """
  @spec remove_runtime_mfas!(t, [mfa]) :: t
  def remove_runtime_mfas!(%{pid: pid} = call_graph, runtime_mfas) do
    update_graph(
      pid,
      fn graph ->
        runtime_mfas_map_set = MapSet.new(runtime_mfas)

        %Digraph{
          vertices: Map.drop(graph.vertices, runtime_mfas),
          outgoing_edges: remove_edges_of_vertices(graph.outgoing_edges, runtime_mfas_map_set),
          incoming_edges: remove_edges_of_vertices(graph.incoming_edges, runtime_mfas_map_set)
        }
      end
    )

    call_graph
  end

  @doc """
  Removes the vertex from the call graph.
  """
  @spec remove_vertex(t, vertex) :: t
  def remove_vertex(%{pid: pid} = call_graph, vertex) do
    update_graph(pid, &Digraph.remove_vertex(&1, vertex))
    call_graph
  end

  @doc """
  Removes the vertices from the call graph.

  Benchmarks: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/call_graph/remove_vertices_2/README.md
  """
  @spec remove_vertices(t, [vertex]) :: t
  def remove_vertices(%{pid: pid} = call_graph, vertices) do
    update_graph(pid, &Digraph.remove_vertices(&1, vertices))
    call_graph
  end

  @doc """
  Returns what the runtime's own reflection calls open for every page (see
  `Hologram.Compiler.ReflectionGate`): the reflection functions, as `{name, arity}` tuples, that a
  function among the given runtime MFAs calls on a module its code does not name. Every page loads
  the runtime, so what its functions can call, any page can.

  Called on the graph that still holds the runtime's MFAs: the pages graph has them and their
  reflection sites' edges taken out (see remove_runtime_mfas!/2).

  The walk runs inside the call graph's agent, so the graph is not copied out.
  """
  @spec runtime_reflection(t, [mfa]) :: runtime_reflection
  def runtime_reflection(call_graph, runtime_mfas) do
    read_graph(call_graph.pid, fn graph ->
      open =
        for mfa <- runtime_mfas,
            {_mfa, {:reflection_site, _function, name, arity, _kind}} <-
              Digraph.outgoing_edges(graph, mfa),
            into: MapSet.new() do
          {name, arity}
        end

      %{open: open}
    end)
  end

  @doc """
  Returns the server callback analysis of each given templatable module: the
  protocol dispatch types that can appear in its server-executed code (code
  reachable from its init/3 and command/3 callbacks) and the component modules
  referenced in its server-executed code.
  Templatables are analyzed sequentially, since spawning a task per templatable
  would copy the whole graph into each task process, which costs far more than
  the traversals themselves.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/call_graph/server_callback_analysis_by_templatable_3/README.md
  """
  @spec server_callback_analysis_by_templatable(Digraph.t(), [module], PLT.t() | nil) ::
          %{module => server_callback_analysis}
  def server_callback_analysis_by_templatable(graph, templatables, module_info_plt) do
    Map.new(templatables, fn templatable ->
      # One traversal feeds both the dispatch types and the referenced components,
      # matching what server_protocol_dispatch_types/2 would traverse for a single
      # templatable.
      server_vertices =
        Digraph.reachable(
          graph,
          [{templatable, :command, 3}, {templatable, :init, 3}],
          opaque_vertex?: &protocol_function_mfa?(&1, module_info_plt)
        )

      analysis = %{
        dispatch_types: protocol_dispatch_types(server_vertices, module_info_plt),
        server_referenced_components:
          extract_component_module_vertices(server_vertices, module_info_plt)
      }

      {templatable, analysis}
    end)
  end

  @doc """
  Returns the set of types that can appear at protocol dispatch in server-executed
  code of the given templatable modules, i.e. code reachable from their init/3 and
  command/3 functions.
  Protocol function vertices are opaque during the traversal, so consolidated
  dispatch edges don't make every loaded implementation's type count as reachable.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/call_graph/server_protocol_dispatch_types_3/README.md
  """
  @spec server_protocol_dispatch_types(Digraph.t(), [module], PLT.t() | nil) :: MapSet.t(module)
  def server_protocol_dispatch_types(graph, templatables, module_info_plt) do
    entry_mfas =
      for templatable <- templatables, function <- [:command, :init] do
        {templatable, function, 3}
      end

    graph
    |> Digraph.reachable(entry_mfas, opaque_vertex?: &protocol_function_mfa?(&1, module_info_plt))
    |> protocol_dispatch_types(module_info_plt)
  end

  @doc """
  Returns sorted call graph edges.
  """
  @spec sorted_edges(t) :: [edge]
  def sorted_edges(%{pid: pid}) do
    read_graph(pid, &Digraph.sorted_edges/1)
  end

  @doc """
  Returns sorted call graph vertices.
  """
  @spec sorted_vertices(t) :: [vertex]
  def sorted_vertices(%{pid: pid}) do
    read_graph(pid, &Digraph.sorted_vertices/1)
  end

  @doc """
  Starts a new call graph agent.

  ## Options

    * `:graph` - the initial `Digraph` to seed the agent with; defaults to an empty graph.
    * `:module_info_plt` - the module info PLT (see `Hologram.Compiler.build_module_info_plt!/3`)
      the graph answers module questions from; defaults to none, under which every module fact is false.
    * `:modules` - the modules whose definitions the graph holds (see `modules/1`); defaults to none.
    * `:reach` - what the walk of `build_reach/3` reached on the graph; defaults to nothing.
    * `:supervisor` - a `DynamicSupervisor` to start the agent under as a `:temporary` child;
      when omitted the agent is linked to the calling process.
  """
  @spec start(T.opts()) :: t
  def start(opts \\ []) do
    state = %{
      graph: opts[:graph] || Digraph.new(),
      modules: opts[:modules] || MapSet.new(),
      reach: opts[:reach] || empty_reach()
    }

    module_info_plt = opts[:module_info_plt]

    {:ok, pid} =
      case opts[:supervisor] do
        nil ->
          Agent.start_link(fn -> state end)

        sup ->
          child_spec = %{
            id: :call_graph,
            restart: :temporary,
            start: {Agent, :start_link, [fn -> state end]}
          }

          DynamicSupervisor.start_child(sup, child_spec)
      end

    %CallGraph{pid: pid, module_info_plt: module_info_plt}
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
  Returns the module the given vertex belongs to: the module of an MFA, the module a module vertex
  is, and the module of the function a reflection site was found in.
  """
  @spec vertex_module(vertex) :: module
  def vertex_module({:reflection_site, {module, _function, _arity}, _name, _arity_2, _kind}),
    do: module

  def vertex_module({module, _function, _arity}), do: module
  def vertex_module(module), do: module

  @doc """
  Returns call graph vertices.
  """
  @spec vertices(t) :: [vertex]
  def vertices(%{pid: pid}) do
    read_graph(pid, &Digraph.vertices/1)
  end

  @doc """
  Runs the function with a reader of the call graph's current graph, shared with every process
  through :persistent_term: the graph is copied out of the Agent once, each call of the reader
  returns it without copying, and it is released when the function returns or raises. The graph
  is the one at the time of the call; edits made to the call graph meanwhile are not seen.

  Pass the reader, not the graph, into the tasks that need it: a closure that captures the graph
  copies it into every task it starts, and the reader captures only the key.
  """
  @spec with_shared_graph(t, ((-> Digraph.t()) -> result)) :: result when result: term
  def with_shared_graph(%{pid: pid}, fun) do
    key = {__MODULE__, make_ref()}

    # The put runs in the Agent, so the graph goes from the Agent's heap straight into the
    # shared area, and the caller never holds a copy.
    read_graph(pid, &:persistent_term.put(key, &1))

    try do
      fun.(fn -> :persistent_term.get(key) end)
    after
      :persistent_term.erase(key)
    end
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
    funs = protocol_functions(module, call_graph.module_info_plt)
    impls = Reflection.list_protocol_implementations(module, call_graph.module_info_plt)

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

  # The reflection functions (see Hologram.Compiler.ReflectionSites) of the types that can appear at
  # protocol dispatch on the page, the way protocol implementations are entered for them: a type's
  # __struct__/0,1 when it is a struct, its __changeset__/0 and __schema__/1,2 when it is an Ecto
  # schema, and only the functions the gate opens (see Hologram.Compiler.ReflectionGate). A named
  # call of a reflection function reaches it through an ordinary edge and needs none of this.
  # TODO: #938. The types come from every module the server callbacks name. Once the compiler knows
  # which types can reach the client, this set shrinks with the protocol implementations' one.
  defp add_reflection_mfas(page_mfas, types, open_functions, module_info_plt) do
    added_mfas =
      for type <- types,
          {name, arity} <- open_functions,
          reflection_function?(type, name, module_info_plt) do
        {type, name, arity}
      end

    page_mfas ++ added_mfas
  end

  # An edge from the function to each reflection site its clause holds, so that the site is replaced
  # with the function when its module is patched, and dumped with the graph.
  defp add_reflection_site_edges(
         call_graph,
         {_module, _function, _arity} = fun_def_vertex,
         clause
       ) do
    edges =
      for {name, arity, kind} <- ReflectionSites.list(clause) do
        {fun_def_vertex, {:reflection_site, fun_def_vertex, name, arity, kind}}
      end

    add_edges(call_graph, edges)
  end

  # A broadcast caller's functions that call a broadcast function, which broadcast_caller_analysis/2
  # walks from.
  defp broadcast_caller_entries(graph, module, module_info_plt) do
    if flag?(module_info_plt, module, :broadcast_caller?) do
      for broadcast_mfa <- Reflection.broadcast_mfas(),
          {caller_vertex, _broadcast_mfa} <- Digraph.incoming_edges(graph, broadcast_mfa),
          vertex_module(caller_vertex) == module,
          uniq: true do
        caller_vertex
      end
    else
      []
    end
  end

  # Walks a round, builds the modules it asks for, and goes on until a round asks for none.
  defp build_reach_rounds(call_graph, entries, build_modules, built_modules) do
    %{pid: pid, module_info_plt: module_info_plt} = call_graph

    {frontier_modules, next_entries} =
      Agent.get_and_update(pid, &walk_reach(&1, entries, module_info_plt), :infinity)

    if frontier_modules == [] do
      built_modules
    else
      build_modules.(frontier_modules)

      build_reach_rounds(
        call_graph,
        next_entries,
        build_modules,
        built_modules ++ frontier_modules
      )
    end
  end

  defp empty_reach do
    %{
      pending_impl_candidates: [],
      reached_vertices: MapSet.new(),
      templatables: MapSet.new(),
      types: MapSet.new(@built_in_protocol_types)
    }
  end

  # An Elixir-named module exists when the module info PLT has an entry for it (one ETS lookup);
  # an Erlang-named one is asked the usual way, and those are the handful of stdlib modules the
  # VM has loaded already.
  defp existing_module?(module, module_info_plt) do
    if Reflection.alias?(module) do
      module_info_plt != nil and PLT.member?(module_info_plt, module)
    else
      Reflection.module?(module)
    end
  end

  # Walks from the given entries with the rules of expand_reachable_state/4, then from what the
  # listings add to what that reached: the dispatch helpers of the reached protocol functions, and
  # the module vertex and server callbacks of each component reached for the first time. Returns the
  # grown reach and the entries that are not vertices of the graph (a function of a module not built
  # yet, or one no module defines).
  defp expand_reach(graph, reach, entries, module_info_plt) do
    expanded_reach = expand_reachable_state(graph, reach, entries, module_info_plt)

    new_vertices =
      expanded_reach.reached_vertices
      |> MapSet.difference(reach.reached_vertices)
      |> MapSet.to_list()

    new_templatables =
      new_vertices
      |> Enum.map(&vertex_module/1)
      |> Enum.uniq()
      |> Enum.filter(
        &(flag?(module_info_plt, &1, :component?) and not MapSet.member?(reach.templatables, &1))
      )

    new_reach = %{
      expanded_reach
      | pending_impl_candidates: Enum.uniq(expanded_reach.pending_impl_candidates),
        templatables: MapSet.union(reach.templatables, MapSet.new(new_templatables))
    }

    missing_entries = Enum.reject(entries, &Digraph.has_vertex?(graph, &1))

    more_entries =
      graph
      |> protocol_dispatch_helper_entry_vertices(new_vertices, module_info_plt)
      |> Enum.concat(Enum.flat_map(new_templatables, &templatable_entries/1))
      |> Enum.reject(&MapSet.member?(new_reach.reached_vertices, &1))
      |> Enum.uniq()

    if more_entries == [] do
      {new_reach, missing_entries}
    else
      {final_reach, more_missing_entries} =
        expand_reach(graph, new_reach, more_entries, module_info_plt)

      {final_reach, missing_entries ++ more_missing_entries}
    end
  end

  # Runs protocol-aware reachability rounds until no new implementations become
  # reachable. Each round traverses only vertices not yet in the state, extends the
  # dispatch types only from the newly reached vertices, and evaluates only the new
  # implementation candidates plus the pending ones against the grown type set.
  defp expand_reachable_state(graph, state, entry_vertices, module_info_plt) do
    new_vertices =
      Digraph.reachable(graph, entry_vertices,
        opaque_vertex?: &protocol_function_mfa?(&1, module_info_plt),
        visited_vertices: state.reached_vertices
      )

    reached_vertices = MapSet.union(state.reached_vertices, MapSet.new(new_vertices))
    types = put_protocol_dispatch_types(state.types, new_vertices, module_info_plt)

    pending_impl_candidates =
      extract_impl_candidates(graph, new_vertices, module_info_plt) ++
        state.pending_impl_candidates

    new_state = %{
      state
      | reached_vertices: reached_vertices,
        types: types,
        pending_impl_candidates: pending_impl_candidates
    }

    promote_pending_impl_candidates(graph, new_state, module_info_plt)
  end

  # A component module referenced in server-executed code can reach the client as a
  # runtime value - put into state by init/3 or sent in action params by command/3 -
  # and render as a dynamic tag, so its client code must be included in the page
  # bundle. Newly included components introduce new templatables (their own server
  # callbacks and the components statically referenced by their client code), so the
  # expansion loops until no new components appear.
  defp expand_reachable_state_with_server_referenced_components(
         graph,
         state,
         templatables,
         analyses,
         module_info_plt
       ) do
    # The analyses are read from the PLT, and computed into it as templatables turn up.
    new_components =
      templatables
      |> Enum.flat_map(fn templatable ->
        server_callback_analysis(graph, templatable, analyses, module_info_plt).server_referenced_components
      end)
      |> Enum.uniq()
      |> Kernel.--(templatables)

    if new_components == [] do
      {state, templatables}
    else
      new_state = expand_reachable_state(graph, state, new_components, module_info_plt)

      newly_reached_components =
        new_state.reached_vertices
        |> MapSet.difference(state.reached_vertices)
        |> Enum.filter(&is_tuple/1)
        |> extract_uniq_components(module_info_plt)

      new_templatables = Enum.uniq(templatables ++ new_components ++ newly_reached_components)

      expand_reachable_state_with_server_referenced_components(
        graph,
        new_state,
        new_templatables,
        analyses,
        module_info_plt
      )
    end
  end

  # Resumes the fixpoint from the given state with additional dispatch types,
  # reaching exactly the vertices a from-scratch run with those types would reach.
  defp expand_reachable_state_with_types(graph, state, extra_types, module_info_plt) do
    new_state = %{state | types: MapSet.union(state.types, extra_types)}
    promote_pending_impl_candidates(graph, new_state, module_info_plt)
  end

  defp extract_component_module_vertices(vertices, module_info_plt) do
    Enum.filter(vertices, &(is_atom(&1) && flag?(module_info_plt, &1, :component?)))
  end

  # Implementation candidates are read from the dispatch edges added at build time
  # (and refreshed on patch), which is much cheaper than listing implementations
  # via reflection, since that scans BEAM files on disk.
  defp extract_impl_candidates(graph, vertices, module_info_plt) do
    for {_protocol, function, arity} = vertex <- vertices,
        protocol_function_mfa?(vertex, module_info_plt),
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

  defp extract_uniq_components(vertices, module_info_plt) do
    vertices
    |> Enum.map(&vertex_module/1)
    |> Enum.uniq()
    |> Enum.filter(&flag?(module_info_plt, &1, :component?))
  end

  # A module the compile knows nothing about (no beam, or an Erlang module) has every flag
  # false, which is what the Reflection predicates answer for it. The PLT is an ETS table
  # every process shares, so the lookup copies one entry, never the table.
  # A module fact from the PLT: nil when there is no PLT, no entry, or the entry has no such key
  # (a dump written before the key existed).
  defp fact(nil, _module, _key), do: nil

  defp fact(module_info_plt, module, key) do
    case PLT.get(module_info_plt, module) do
      {:ok, info} -> Map.get(info, key)
      :error -> nil
    end
  end

  defp flag?(nil, _module, _flag), do: false

  defp flag?(module_info_plt, module, flag) do
    match?({:ok, %{^flag => true}}, PLT.get(module_info_plt, module))
  end

  defp finalize_reachable_mfas(graph, state, module_info_plt) do
    reached_vertices = MapSet.to_list(state.reached_vertices)

    helper_vertices =
      protocol_dispatch_dependency_vertices(graph, reached_vertices, module_info_plt)

    vertices = Enum.uniq(reached_vertices ++ helper_vertices)

    Enum.filter(vertices, fn
      # Some protocol implementations are referenced but not actually implemented, e.g. Collectable.Atom
      {module, _function, _arity} -> existing_module?(module, module_info_plt)
      _module_vertex -> false
    end)
  end

  # Whether a reached vertex needs its module built before its edges are complete: a function of a
  # module the graph holds no definition of and the module info PLT knows (an Erlang module has no
  # IR, a module the PLT does not know has no beam), or the vertex of such a module when building it
  # would give that vertex edges. A reflection site exists only once its function's module is built.
  defp frontier_vertex?({:reflection_site, _mfa, _name, _arity, _kind}, _modules, _module_infos),
    do: false

  defp frontier_vertex?({module, _function, _arity}, graph_modules, module_info_plt) do
    unbuilt_module?(module, graph_modules, module_info_plt)
  end

  defp frontier_vertex?(module, graph_modules, module_info_plt) do
    unbuilt_module?(module, graph_modules, module_info_plt) and
      Enum.any?(@module_vertex_edge_flags, &flag?(module_info_plt, module, &1))
  end

  # The reached functions of the protocol an added or edited implementation implements, walked
  # again so that the dispatch edges the patch refreshed are read as implementation candidates.
  defp implementation_entries(module, graph_modules, reach, module_info_plt) do
    if implementation_of_graph_protocol?(module, graph_modules, module_info_plt) do
      protocol = implemented_protocol(module, module_info_plt)

      for {function, arity} <- protocol_functions(protocol, module_info_plt),
          vertex = {protocol, function, arity},
          MapSet.member?(reach.reached_vertices, vertex) do
        vertex
      end
    else
      []
    end
  end

  # The four facts the traversal used to get by calling the module, each with that call as the
  # fallback for a PLT that has no answer. A nil fact means the value could not be read from the
  # beam (no PLT, no entry, an old dump, a function whose value is computed rather than a
  # literal), never that the module has no such value: a page without a layout is rejected by
  # Compiler.validate_page_modules/2 before any traversal, so calling the module is right.
  defp implementation_for(impl, module_info_plt) do
    fact(module_info_plt, impl, :implementation_for) || impl.__impl__(:for)
  end

  # The flag comes first: implemented_protocol/2 asks the module when the PLT has no literal, which
  # only an implementation can answer.
  defp implementation_of_graph_protocol?(module, graph_modules, module_info_plt) do
    flag?(module_info_plt, module, :protocol_implementation?) and
      MapSet.member?(graph_modules, implemented_protocol(module, module_info_plt))
  end

  defp implemented_protocol(impl, module_info_plt) do
    fact(module_info_plt, impl, :implemented_protocol) || impl.__impl__(:protocol)
  end

  defp incoming_edges(%{pid: pid}, vertex) do
    read_graph(pid, &Digraph.incoming_edges(&1, vertex))
  end

  defp layout_module(page_module, module_info_plt) do
    fact(module_info_plt, page_module, :layout_module) || page_module.__layout_module__()
  end

  defp list_async_mfas_in_graph(graph) do
    graph
    |> Digraph.reaching([{Task, :await, 1}], opaque_vertex?: &is_atom/1)
    # Excludes bare module atom vertices, keeping only MFA tuples.
    # No Reflection.module?/1 guard needed in the filter (unlike reachable_mfas/2) because
    # the result is only used for MapSet.member? lookups against already-included MFAs.
    |> Enum.filter(&is_tuple/1)
    |> MapSet.new()
  end

  defp list_modules_reaching_in_graph(graph, target_modules, module_info_plt) do
    # One pass over the vertices rather than a scan per module: the graph holds a vertex per
    # function of the app.
    target_vertices =
      graph
      |> Digraph.vertices()
      |> Enum.filter(&MapSet.member?(target_modules, vertex_module(&1)))

    protocol_function_mfa? = &protocol_function_mfa?(&1, module_info_plt)

    graph
    |> Digraph.reaching(target_vertices, opaque_vertex?: protocol_function_mfa?)
    # A protocol's dispatch function is where the reverse walk stops, and it is dropped with the
    # walk: a page that calls the protocol carries only the implementations of its own types, and
    # it holds each of those modules in its kept modules, so the pages an edited implementation
    # affects are found by that intersection rather than through the dispatch edges. Editing a
    # protocol module itself still reaches its callers, since the target modules are unioned back in.
    |> Enum.reject(protocol_function_mfa?)
    |> MapSet.new(&vertex_module/1)
    |> MapSet.union(target_modules)
  end

  defp list_runtime_mfas_in_graph(graph, pages, module_info_plt) do
    entry_mfas = list_runtime_entry_mfas()

    # A component module referenced in broadcast caller code can be delivered to any
    # connected page as a runtime value (e.g. in broadcast action params) and render
    # as a dynamic tag there, so its client code goes into the runtime bundle, which
    # every page loads.
    broadcast_caller_analysis = broadcast_caller_analysis(graph, module_info_plt)

    app_types =
      app_protocol_dispatch_types(graph, pages, broadcast_caller_analysis, module_info_plt)

    entry_vertices = entry_mfas ++ broadcast_caller_analysis.referenced_components
    initial_state = start_reachable_state(graph, entry_vertices, app_types, module_info_plt)
    initial_mfas = Enum.filter(initial_state.reached_vertices, &is_tuple/1)

    initial_templatables =
      Enum.uniq(
        broadcast_caller_analysis.referenced_components ++
          extract_uniq_components(initial_mfas, module_info_plt)
      )

    # The same server-referenced component expansion as in list_page_mfas/5, so chains
    # like a broadcast-referenced component whose own server callbacks reference
    # further components end up in the runtime bundle too. The runtime lists against a PLT
    # of its own, filled on demand and stopped once the MFAs are listed: its analyses are
    # taken on the graph that still holds the runtime's functions, so they must not mix
    # with the pages'.
    analyses = PLT.start()

    {expanded_state, templatables} =
      expand_reachable_state_with_server_referenced_components(
        graph,
        initial_state,
        initial_templatables,
        analyses,
        module_info_plt
      )

    server_types =
      Enum.reduce(templatables, MapSet.new(), fn templatable, acc ->
        analysis = server_callback_analysis(graph, templatable, analyses, module_info_plt)
        MapSet.union(acc, analysis.dispatch_types)
      end)

    PLT.stop(analyses)

    final_state =
      expand_reachable_state_with_types(graph, expanded_state, server_types, module_info_plt)

    graph
    |> finalize_reachable_mfas(final_state, module_info_plt)
    |> reject_hex_mfas()
    |> Enum.sort()
  end

  defp maybe_add_ecto_schema_call_graph_edges(call_graph, module) do
    if module_flag?(call_graph, module, :ecto_schema?) do
      add_edges(call_graph, [
        {module, {module, :__changeset__, 0}},
        {module, {module, :__schema__, 1}},
        {module, {module, :__schema__, 2}}
      ])
    end

    call_graph
  end

  defp maybe_add_error_info_formatter_edge(
         call_graph,
         %IR.ListType{data: options},
         from_vertex
       ) do
    error_info_pairs =
      Enum.find_value(options, fn
        %IR.TupleType{
          data: [%IR.AtomType{value: :error_info}, %IR.MapType{data: pairs}]
        } ->
          {:ok, pairs}

        _option ->
          nil
      end)

    default_module =
      case from_vertex do
        {module, _function, _arity} -> module
        module when is_atom(module) -> module
      end

    with {:ok, pairs} <- error_info_pairs,
         {:ok, format_module} <- resolve_error_info_key(pairs, :module, default_module),
         {:ok, format_function} <- resolve_error_info_key(pairs, :function, :format_error) do
      add_edge(call_graph, from_vertex, {format_module, format_function, 2})
    else
      _fallback -> call_graph
    end
  end

  defp maybe_add_error_info_formatter_edge(call_graph, _options, _from_vertex) do
    call_graph
  end

  defp maybe_add_protocol_call_graph_edges(call_graph, module) do
    if module_flag?(call_graph, module, :protocol?) do
      add_protocol_call_graph_edges(call_graph, module)
    end

    call_graph
  end

  # Exception.message/1 dispatches on the module of the struct it is given, so
  # the callback isn't reachable from any call site - a reached exception
  # module brings its own.
  defp maybe_add_exception_call_graph_edges(call_graph, module) do
    if module_flag?(call_graph, module, :exception?) do
      add_edge(call_graph, module, {module, :message, 1})
    end

    call_graph
  end

  defp maybe_add_struct_call_graph_edges(call_graph, module) do
    if module_flag?(call_graph, module, :struct?) do
      add_edges(call_graph, [
        {module, {module, :__struct__, 0}},
        {module, {module, :__struct__, 1}}
      ])
    end

    call_graph
  end

  defp maybe_add_templatable_call_graph_edges(call_graph, module) do
    if module_flag?(call_graph, module, :page?) do
      add_page_call_graph_edges(call_graph, module)
    end

    if module_flag?(call_graph, module, :component?) do
      add_component_call_graph_edges(call_graph, module)
    end

    call_graph
  end

  defp maybe_put_struct_type(types, module, module_info_plt) do
    if flag?(module_info_plt, module, :struct?) do
      MapSet.put(types, module)
    else
      types
    end
  end

  # What the walk starts from for an added or edited module, by kind; nothing for a module of no
  # such kind, whose changed calls are walked again from its reached functions (see reach_entries/3).
  defp module_entries(module, state, module_info_plt) do
    %{graph: graph, modules: graph_modules, reach: reach} = state

    page_entries(module, module_info_plt) ++
      broadcast_caller_entries(graph, module, module_info_plt) ++
      implementation_entries(module, graph_modules, reach, module_info_plt)
  end

  defp module_flag?(%CallGraph{module_info_plt: module_info_plt}, module, flag) do
    flag?(module_info_plt, module, flag)
  end

  # A page's client entries (its own and its layout's) and its server callbacks.
  defp page_entries(module, module_info_plt) do
    if flag?(module_info_plt, module, :page?) do
      list_page_entry_mfas(module, module_info_plt) ++ server_entries(module)
    else
      []
    end
  end

  # Moves pending implementation candidates whose target type has become reachable
  # into the traversal, continuing rounds until none are promotable.
  defp promote_pending_impl_candidates(graph, state, module_info_plt) do
    {ready_candidates, pending_impl_candidates} =
      Enum.split_with(state.pending_impl_candidates, fn {impl, _impl_entry_vertices} ->
        protocol_implementation_reachable?(impl, state.types, module_info_plt)
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
      expand_reachable_state(graph, new_state, impl_entry_vertices, module_info_plt)
    end
  end

  # The same-module dispatch helpers (impl_for/1, impl_for!/1 and the like) the given protocol
  # function vertices call.
  defp protocol_dispatch_helper_entry_vertices(graph, vertices, module_info_plt) do
    for vertex <- vertices,
        protocol_function_mfa?(vertex, module_info_plt),
        {_source_vertex, target_vertex} <- Digraph.outgoing_edges(graph, vertex),
        protocol_dispatch_helper_mfa?(vertex, target_vertex, module_info_plt) do
      target_vertex
    end
  end

  defp protocol_dispatch_helper_mfa?(
         {protocol, _function, _arity},
         {protocol, _helper_function, _helper_arity} = target_vertex,
         module_info_plt
       ) do
    !protocol_function_mfa?(target_vertex, module_info_plt)
  end

  defp protocol_dispatch_helper_mfa?(_vertex, _target_vertex, _module_infos), do: false

  # The flag keeps the function list lookup off every module that is not a protocol.
  defp protocol_function_mfa?({module, function, arity}, module_info_plt) do
    flag?(module_info_plt, module, :protocol?) and
      {function, arity} in protocol_functions(module, module_info_plt)
  end

  defp protocol_function_mfa?(_vertex, _module_infos), do: false

  defp protocol_functions(module, module_info_plt) do
    fact(module_info_plt, module, :protocol_functions) || module.__protocol__(:functions)
  end

  defp protocol_implementation_reachable?(impl, types, module_info_plt) do
    flag?(module_info_plt, impl, :protocol_implementation?) and
      MapSet.member?(types, implementation_for(impl, module_info_plt))
  end

  # Bodies of functions generated by defprotocol (__protocol__/1, impl_for/1, impl_for!/1,
  # struct_impl_for/1) and defimpl (__impl__/1) enumerate module atoms (implementation
  # modules, dispatch target types, the protocol itself) that are metadata, not dependencies.
  defp protocol_metadata_mfa?({module, function, 1}, module_info_plt)
       when function in [:__protocol__, :impl_for, :impl_for!, :struct_impl_for] do
    flag?(module_info_plt, module, :protocol?)
  end

  defp protocol_metadata_mfa?({module, :__impl__, 1}, module_info_plt) do
    flag?(module_info_plt, module, :protocol_implementation?)
  end

  defp protocol_metadata_mfa?(_vertex, _module_infos), do: false

  # Whether the type defines the reflection function: a struct defines __struct__/0,1, an Ecto schema
  # __changeset__/0 and __schema__/1,2. The built-in protocol dispatch types define none.
  defp reflection_function?(type, :__struct__, module_info_plt) do
    flag?(module_info_plt, type, :struct?)
  end

  defp reflection_function?(type, _name, module_info_plt) do
    flag?(module_info_plt, type, :ecto_schema?)
  end

  # Records the module as one whose definition is built into the graph (see modules/1).
  defp put_module(%{pid: pid} = call_graph, module) do
    Agent.cast(pid, fn state -> %{state | modules: MapSet.put(state.modules, module)} end)
    call_graph
  end

  defp put_protocol_dispatch_types(types, vertices, module_info_plt) do
    Enum.reduce(vertices, types, fn
      module, acc when is_atom(module) ->
        maybe_put_struct_type(acc, module, module_info_plt)

      {module, :__struct__, arity}, acc when arity in [0, 1] ->
        MapSet.put(acc, module)

      _vertex, acc ->
        acc
    end)
  end

  # The entries a walk starts from after a patch with the given diff, and the reach it starts with:
  # the reached vertices of the removed and edited modules are forgotten, those of the edited ones
  # walked again, since the patch gave them their new calls. So are the templatables among them,
  # which the walk finds again through those vertices, reaching the server callbacks and client
  # entries they may have gained. Every entry is taken out of the reach, so that it is walked with
  # its edges as they are now.
  defp reach_entries(%{reach: reach} = state, diff, module_info_plt) do
    replaced_modules = MapSet.new(diff.removed_modules ++ diff.edited_modules)
    edited_modules = MapSet.new(diff.edited_modules)

    {replaced_vertices, kept_vertex_list} =
      Enum.split_with(
        reach.reached_vertices,
        &MapSet.member?(replaced_modules, vertex_module(&1))
      )

    reentries = Enum.filter(replaced_vertices, &MapSet.member?(edited_modules, vertex_module(&1)))
    kept_vertices = MapSet.new(kept_vertex_list)

    runtime_entries = Enum.reject(list_runtime_entry_mfas(), &MapSet.member?(kept_vertices, &1))

    kind_entries =
      Enum.flat_map(
        diff.added_modules ++ diff.edited_modules,
        &module_entries(&1, state, module_info_plt)
      )

    entries = Enum.uniq(runtime_entries ++ reentries ++ kind_entries)

    pending_impl_candidates =
      Enum.reject(reach.pending_impl_candidates, fn {impl, _impl_entry_vertices} ->
        impl in diff.removed_modules
      end)

    new_reach = %{
      reach
      | pending_impl_candidates: pending_impl_candidates,
        reached_vertices: MapSet.difference(kept_vertices, MapSet.new(entries)),
        templatables: MapSet.difference(reach.templatables, replaced_modules)
    }

    {entries, new_reach}
  end

  # Runs the function on the agent's graph inside the agent, so that only its result is copied out.
  defp read_graph(pid, fun) do
    Agent.get(pid, &fun.(&1.graph), :infinity)
  end

  # When modules that are protocol implementations are added or edited, the protocol
  # module itself (e.g. Enumerable) is unchanged and not re-processed by patch. Its
  # dispatch edges remain stale. This function re-runs add_protocol_call_graph_edges
  # for each affected protocol so dispatch edges reflect the current set of implementations.
  # A protocol among the added or edited modules was just built, with its edges taken from
  # the same PLT, so it is skipped. Removed modules are excluded because
  # add_protocol_call_graph_edges auto-creates vertices, which would re-introduce vertices
  # that remove_module_vertices already cleaned up.
  defp refresh_protocol_dispatch_edges(call_graph, added_or_edited_modules) do
    built_modules = MapSet.new(added_or_edited_modules)

    added_or_edited_modules
    |> Enum.filter(&module_flag?(call_graph, &1, :protocol_implementation?))
    |> Enum.map(&implemented_protocol(&1, call_graph.module_info_plt))
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(built_modules, &1))
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

  # An edge map (outgoing or incoming) without the given vertices, whether as the vertex an entry is
  # for or among its neighbours. An entry left with no neighbour is dropped, as a graph built edge by
  # edge has none.
  defp remove_edges_of_vertices(edges, vertices) do
    for {vertex, neighbours} <- edges,
        not MapSet.member?(vertices, vertex),
        kept_neighbours <- [
          Map.reject(neighbours, fn {neighbour, _flag} -> MapSet.member?(vertices, neighbour) end)
        ],
        map_size(kept_neighbours) > 0,
        into: %{} do
      {vertex, kept_neighbours}
    end
  end

  defp remove_module_vertices(%{pid: pid} = call_graph, module) do
    remove_vertices(call_graph, module_vertices(call_graph, module))
    Agent.cast(pid, fn state -> %{state | modules: MapSet.delete(state.modules, module)} end)
    call_graph
  end

  # Resolves an error_info map key to an atom: an absent key resolves to the
  # default, a literal atom value resolves to itself, and anything dynamic
  # (or a nil default) makes the resolution fail.
  defp resolve_error_info_key(pairs, key, default) do
    found = Enum.find(pairs, fn {k, _v} -> match?(%IR.AtomType{value: ^key}, k) end)

    case found do
      {_key_ir, %IR.AtomType{value: value}} -> {:ok, value}
      nil when is_nil(default) -> :error
      nil -> {:ok, default}
      _fallback -> :error
    end
  end

  # A templatable's server callback analysis, from the PLT when it holds one, else computed and
  # put there for the pages listed after this one.
  defp server_callback_analysis(graph, templatable, analyses, module_info_plt) do
    case PLT.get(analyses, templatable) do
      {:ok, analysis} ->
        analysis

      :error ->
        analysis =
          graph
          |> server_callback_analysis_by_templatable([templatable], module_info_plt)
          |> Map.fetch!(templatable)

        PLT.put(analyses, templatable, analysis)
        analysis
    end
  end

  defp server_entries(module), do: [{module, :command, 3}, {module, :init, 3}]

  # Runs the protocol-aware fixpoint from the given entry vertices and returns the
  # resulting state: the reached vertex set, the accumulated dispatch types, and the
  # implementation candidates whose target types are not reachable yet.
  defp start_reachable_state(graph, entry_vertices, extra_types, module_info_plt) do
    initial_types =
      @built_in_protocol_types
      |> MapSet.new()
      |> MapSet.union(extra_types)

    state = %{
      reached_vertices: MapSet.new(),
      types: initial_types,
      pending_impl_candidates: []
    }

    expand_reachable_state(graph, state, entry_vertices, module_info_plt)
  end

  # A component's module vertex, which carries the edges to its client functions, and its server
  # callbacks.
  defp templatable_entries(module), do: [module | server_entries(module)]

  defp unbuilt_module?(module, graph_modules, module_info_plt) do
    not MapSet.member?(graph_modules, module) and PLT.member?(module_info_plt, module)
  end

  # Replaces the agent's graph with what the function makes of it, keeping the modules and the reach.
  defp update_graph(pid, fun) do
    Agent.cast(pid, fn state -> %{state | graph: fun.(state.graph)} end)
  end

  # One round of build_reach/3, run inside the agent: walks from the given entries, and returns the
  # modules the reached vertices need built (see frontier_vertex?/3) with the entries of the next
  # round: the reached vertices of those modules, taken out of the reach so that the next round walks
  # them with their calls in place, and the entries that are functions of those modules. An entry
  # that is no vertex of a module the graph holds is a function no module defines, and is dropped.
  defp walk_reach(
         %{graph: graph, modules: graph_modules, reach: reach} = state,
         entries,
         module_info_plt
       ) do
    {new_reach, missing_entries} = expand_reach(graph, reach, entries, module_info_plt)

    frontier_vertices =
      new_reach.reached_vertices
      |> MapSet.difference(reach.reached_vertices)
      |> Enum.filter(&frontier_vertex?(&1, graph_modules, module_info_plt))

    frontier_modules =
      frontier_vertices
      |> Enum.concat(missing_entries)
      |> Enum.map(&vertex_module/1)
      |> Enum.filter(&unbuilt_module?(&1, graph_modules, module_info_plt))
      |> Enum.uniq()

    frontier_module_set = MapSet.new(frontier_modules)

    pending_entries =
      Enum.filter(missing_entries, &MapSet.member?(frontier_module_set, vertex_module(&1)))

    next_reach = %{
      new_reach
      | reached_vertices:
          MapSet.difference(new_reach.reached_vertices, MapSet.new(frontier_vertices))
    }

    {{frontier_modules, frontier_vertices ++ pending_entries}, %{state | reach: next_reach}}
  end
end
