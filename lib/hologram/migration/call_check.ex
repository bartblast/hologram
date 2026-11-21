defmodule Hologram.Migration.CallCheck do
  @moduledoc false

  alias Hologram.Migration.FieldAccess.Definitions
  alias Hologram.Migration.Value

  # What a migration does to a row must never change after it is applied, so its code
  # may call only what gives the same result for the same arguments, whatever the app, the
  # machine or the moment: its own functions and the standard library's functions that
  # compute on the values they are given. A call to one of the app's modules, a
  # dependency's or Hologram's would change whenever they do, a call to a module chosen at
  # runtime - through apply/3, Function.capture/3, mod.fun() or a function that evaluates
  # code - whenever the value does, and a read of the clock, the environment, a random
  # source or a time zone database on every run. The allowed functions are listed rather
  # than the others refused, so a function nobody thought of is refused too.
  #
  # Field access on a value, x.field, compiles into a strict map read (see
  # Hologram.Migration.FieldAccess), as Elixir would otherwise call x's function when x
  # holds a module; one the rewrite did not reach is refused. A macro's code is checked like
  # a function's - one the migration itself calls has run by the time the check does, but
  # the build still fails. An Erlang parse transform is refused, as it rewrites the code
  # after the debug info read here.
  #
  # Code that ran while the module compiled - a call in the module body, another module's
  # macro - left only its results in the bytecode, so it is checked through the modules the
  # compiler recorded the migration using at compile time, against the whole of the Elixir
  # and Erlang/OTP standard libraries: the record names modules, not functions, and every
  # module compiles through Module and the compiler's own. The record can't tell a module
  # called from one only named, so reading an attribute holding MyApp.Task in the body - as
  # an op that reads it does - is refused too; a module named in an op itself, or held in an
  # attribute only a function reads, is not used at compile time. The record covers the
  # whole file, so a second module in a migration file is checked along with it.
  #
  # Known blind spots: a standard function given a module as a value calls it - a sorter
  # for Enum.sort/2, a calendar for Date.new/4, and the protocol implementation, Access,
  # message/1 or __escape__/1 of a map given its __struct__ at runtime, File.Stream's among
  # them, which reads and writes files - and so do raising a module held in a variable and
  # an error_info naming one; the module body, which runs once per build, is checked by the
  # modules it used rather than by function, so beyond the environment modules listed below
  # it may read the clock, the machine, files or configuration through other standard
  # functions - Date.utc_today/0, node/0, __DIR__, :filelib - and reach a module chosen at
  # runtime, a listed one or Hologram.Migration among them; a DateTime built by hand in a
  # zone other than UTC sends the date arithmetic to the time zone database; a map's
  # iteration order follows the order its atom keys were created in the VM; inspect/1
  # follows the default inspect function the app may set; an exception's message can name
  # loaded modules; and Logger's level decides whether a log message is built at all.

  # The structs a migration may not build though their module is listed: a URI's port and
  # string form follow the default port the app may set for its scheme, so URI keeps only
  # its functions on strings.
  @refused_structs [URI]

  # The functions a migration may call, by module: :all for a module whose every function
  # computes on its arguments only, otherwise the functions by name, or by name and arity.
  @allowed_functions %{
    Access => :all,
    Atom => :all,
    Base => :all,
    Bitwise => :all,
    Calendar => [:compatible_calendars?, :strftime, :truncate],
    Collectable => [:into],
    Date => [
      :add,
      :after?,
      :before?,
      :beginning_of_month,
      :beginning_of_week,
      :compare,
      :convert,
      :convert!,
      :day_of_era,
      :day_of_week,
      :day_of_year,
      :days_in_month,
      :diff,
      :end_of_month,
      :end_of_week,
      :from_erl,
      :from_erl!,
      :from_gregorian_days,
      :from_iso8601,
      :from_iso8601!,
      :leap_year?,
      :months_in_year,
      :new,
      :new!,
      :quarter_of_year,
      :range,
      :shift,
      :to_erl,
      :to_gregorian_days,
      :to_iso8601,
      :to_iso_days,
      :to_string,
      :year_of_era
    ],
    # Those that take a time zone are left out - they read the time zone database.
    DateTime => [
      :add,
      :after?,
      :before?,
      :compare,
      :convert,
      :convert!,
      :diff,
      :from_gregorian_seconds,
      :from_iso8601,
      :from_unix,
      :from_unix!,
      :shift,
      :to_date,
      :to_gregorian_seconds,
      :to_iso8601,
      :to_naive,
      :to_string,
      :to_time,
      :to_unix,
      :truncate
    ],
    # The struct Date.range/2 returns, which has no functions of its own.
    Date.Range => [],
    Duration => :all,
    # The quote machinery a defguard or a defmacro with unquote compiles into.
    :elixir_quote => :all,
    Enum => [
      # What x in list compiles into on Elixir 1.20.
      :__in__,
      :all?,
      :any?,
      :at,
      :chunk,
      :chunk_by,
      :chunk_every,
      :chunk_while,
      :concat,
      :count,
      :count_until,
      :dedup,
      :dedup_by,
      :drop,
      :drop_every,
      :drop_while,
      :each,
      :empty?,
      :fetch,
      :fetch!,
      :filter,
      :filter_map,
      :find,
      :find_index,
      :find_value,
      :flat_map,
      :flat_map_reduce,
      :frequencies,
      :frequencies_by,
      :group_by,
      :intersperse,
      :into,
      :join,
      :map,
      :map_every,
      :map_intersperse,
      :map_join,
      :map_reduce,
      :max,
      :max_by,
      :member?,
      :min,
      :min_by,
      :min_max,
      :min_max_by,
      :partition,
      :product,
      :product_by,
      :reduce,
      :reduce_while,
      :reject,
      :reverse,
      :reverse_slice,
      :scan,
      :slice,
      :slide,
      :sort,
      :sort_by,
      :split,
      :split_while,
      :split_with,
      :sum,
      :sum_by,
      :take,
      :take_every,
      :take_while,
      :to_list,
      :uniq,
      :uniq_by,
      :unzip,
      :with_index,
      :zip,
      :zip_reduce,
      :zip_with
    ],
    Enumerable => [:count, :member?, :reduce, :slice],
    # Not format/3 and its like, whose stacktraces name the Elixir version and the paths.
    Exception => [:exception?, :message, :normalize],
    Float => :all,
    Function => [:identity],
    Integer => :all,
    IO => [
      :chardata_to_string,
      :iodata_empty?,
      :iodata_length,
      :iodata_to_binary,
      :warn,
      inspect: 1,
      inspect: 2,
      puts: 1,
      write: 1
    ],
    JSON => :all,
    Kernel => [
      :!=,
      :!==,
      :*,
      :**,
      :+,
      :++,
      :-,
      :--,
      :/,
      :<,
      :<=,
      :==,
      :===,
      :=~,
      :>,
      :>=,
      :abs,
      :binary_part,
      :binary_slice,
      :bit_size,
      :byte_size,
      :ceil,
      :div,
      :elem,
      :exit,
      :floor,
      :get_and_update_in,
      :get_in,
      :hd,
      :inspect,
      :is_atom,
      :is_binary,
      :is_bitstring,
      :is_boolean,
      :is_float,
      :is_function,
      :is_integer,
      :is_list,
      :is_map,
      :is_map_key,
      :is_number,
      :is_pid,
      :is_port,
      :is_reference,
      :is_tuple,
      :length,
      :map_size,
      :max,
      :min,
      :not,
      :pop_in,
      :put_elem,
      :put_in,
      :rem,
      :round,
      :throw,
      :tl,
      :trunc,
      :tuple_size,
      :update_in
    ],
    # raise/1 with a message held in a variable.
    Kernel.Utils => [:raise],
    Keyword => :all,
    List => [
      :ascii_printable?,
      :delete,
      :delete_at,
      :duplicate,
      :ends_with?,
      :first,
      :first!,
      :flatten,
      :foldl,
      :foldr,
      :improper?,
      :insert_at,
      :keydelete,
      :keyfind,
      :keyfind!,
      :keymember?,
      :keyreplace,
      :keysort,
      :keystore,
      :keytake,
      :last,
      :last!,
      :myers_difference,
      :pop_at,
      :replace_at,
      :starts_with?,
      :to_atom,
      :to_charlist,
      :to_float,
      :to_integer,
      :to_string,
      :to_tuple,
      :update_at,
      :wrap,
      :zip
    ],
    List.Chars => [:to_charlist],
    # The logging the Logger macros compile into.
    Logger => [:__do_log__, :__should_log__, :bare_log],
    Macro => [:camelize, :escape, :to_string, :underscore, :var],
    # The guard check of a defguard.
    Macro.Env => [:in_guard?],
    # Not from_struct/1, which calls a module given as a value.
    Map => [
      :delete,
      :drop,
      :equal?,
      :fetch,
      :fetch!,
      :filter,
      :from_keys,
      :get,
      :get_and_update,
      :get_and_update!,
      :get_lazy,
      :has_key?,
      :intersect,
      :keys,
      :map,
      :merge,
      :new,
      :pop,
      :pop!,
      :pop_lazy,
      :put,
      :put_new,
      :put_new_lazy,
      :reject,
      :replace,
      :replace!,
      :replace_lazy,
      :size,
      :split,
      :split_with,
      :take,
      :to_list,
      :update,
      :update!,
      :values
    ],
    MapSet => :all,
    NaiveDateTime => [
      :add,
      :after?,
      :before?,
      :beginning_of_day,
      :compare,
      :convert,
      :convert!,
      :diff,
      :end_of_day,
      :from_erl,
      :from_erl!,
      :from_gregorian_seconds,
      :from_iso8601,
      :from_iso8601!,
      :new,
      :new!,
      :shift,
      :to_date,
      :to_erl,
      :to_gregorian_seconds,
      :to_iso8601,
      :to_string,
      :to_time,
      :truncate
    ],
    Range => :all,
    # Not version/0, which names the PCRE build.
    Regex => [
      :compile,
      :compile!,
      :escape,
      :import,
      :match?,
      :named_captures,
      :names,
      :opts,
      :re_pattern,
      :recompile,
      :recompile!,
      :regex?,
      :replace,
      :run,
      :scan,
      :source,
      :split,
      :to_embed
    ],
    Stream => [
      :chunk,
      :chunk_by,
      :chunk_every,
      :chunk_while,
      :concat,
      :cycle,
      :dedup,
      :dedup_by,
      :drop,
      :drop_every,
      :drop_while,
      :duplicate,
      :each,
      :filter,
      :filter_map,
      :flat_map,
      :from_index,
      :intersperse,
      :into,
      :iterate,
      :map,
      :map_every,
      :reject,
      :repeatedly,
      :resource,
      :run,
      :scan,
      :take,
      :take_every,
      :take_while,
      :transform,
      :unfold,
      :uniq,
      :uniq_by,
      :with_index,
      :zip,
      :zip_with
    ],
    String => [
      :at,
      :bag_distance,
      :byte_slice,
      :capitalize,
      :chunk,
      :codepoints,
      :contains?,
      :count,
      :downcase,
      :duplicate,
      :ends_with?,
      :equivalent?,
      :first,
      :graphemes,
      :jaro_distance,
      :last,
      :length,
      :match?,
      :myers_difference,
      :next_codepoint,
      :next_grapheme,
      :next_grapheme_size,
      :normalize,
      :pad_leading,
      :pad_trailing,
      :printable?,
      :replace,
      :replace_invalid,
      :replace_leading,
      :replace_prefix,
      :replace_suffix,
      :replace_trailing,
      :reverse,
      :slice,
      :split,
      :split_at,
      :splitter,
      :starts_with?,
      :to_atom,
      :to_charlist,
      :to_float,
      :to_integer,
      :trim,
      :trim_leading,
      :trim_trailing,
      :upcase,
      :valid?
    ],
    String.Chars => [:to_string],
    Time => [
      :add,
      :after?,
      :before?,
      :compare,
      :convert,
      :convert!,
      :diff,
      :from_erl,
      :from_erl!,
      :from_iso8601,
      :from_iso8601!,
      :from_seconds_after_midnight,
      :new,
      :new!,
      :shift,
      :to_erl,
      :to_iso8601,
      :to_seconds_after_midnight,
      :to_string,
      :truncate
    ],
    Tuple => :all,
    URI => [
      :char_reserved?,
      :char_unescaped?,
      :char_unreserved?,
      :decode,
      :decode_query,
      :decode_www_form,
      :encode,
      :encode_query,
      :encode_www_form,
      :query_decoder
    ],
    :base64 => :all,
    :binary => :all,
    :crypto => [:hash, :hash_final, :hash_init, :hash_update, :mac],
    :io_lib => [:format, :fwrite],
    :lists => :all,
    :maps => :all,
    :math => :all,
    :ordsets => :all,
    :proplists => :all,
    :queue => :all,
    :re => [:compile, :grun, :import, :inspect, :replace, :run, :split],
    :sets => :all,
    :string => :all,
    :unicode => :all,
    :uri_string => :all
  }

  # The :erlang functions that compute on their arguments only - the ones Kernel compiles
  # into, and their like. The rest of :erlang reaches processes, ports, code loading,
  # dispatch, the clock and the node.
  @erlang_functions [
    :*,
    :+,
    :++,
    :-,
    :--,
    :/,
    :"/=",
    :<,
    :"=/=",
    :"=:=",
    :"=<",
    :==,
    :>,
    :>=,
    :abs,
    :and,
    :andalso,
    :append_element,
    :atom_to_binary,
    :atom_to_list,
    :band,
    :binary_part,
    :binary_to_atom,
    :binary_to_float,
    :binary_to_integer,
    :binary_to_list,
    :bit_size,
    :bitstring_to_list,
    :bnot,
    :bor,
    :bsl,
    :bsr,
    :bxor,
    :byte_size,
    :ceil,
    :delete_element,
    :div,
    :element,
    :error,
    :float,
    :float_to_binary,
    :float_to_list,
    :floor,
    :hd,
    :insert_element,
    :integer_to_binary,
    :integer_to_list,
    :iolist_size,
    :iolist_to_binary,
    :is_atom,
    :is_binary,
    :is_bitstring,
    :is_boolean,
    :is_float,
    :is_function,
    :is_integer,
    :is_list,
    :is_map,
    :is_map_key,
    :is_number,
    :is_pid,
    :is_port,
    :is_reference,
    :is_tuple,
    :length,
    :list_to_atom,
    :list_to_binary,
    :list_to_bitstring,
    :list_to_float,
    :list_to_integer,
    :list_to_tuple,
    :make_tuple,
    :map_get,
    :md5,
    :map_size,
    :max,
    :min,
    :not,
    :or,
    :orelse,
    :phash2,
    :raise,
    :rem,
    :round,
    :setelement,
    :split_binary,
    :throw,
    :tl,
    :trunc,
    :tuple_size,
    :tuple_to_list,
    :xor,
    exit: 1
  ]

  # Standard modules that can read the environment, the clock or a random source, or evaluate
  # code - refused at compile time too, where the module body could keep what they return in
  # an attribute an op reads. The record names modules, so their pure functions, like
  # Path.join/2, are refused there along with the rest, and so is a require or an import of
  # one.
  @environment_modules [
    Application,
    Code,
    File,
    Node,
    Path,
    Port,
    Process,
    System,
    :application,
    :code,
    :crypto,
    :ets,
    :file,
    :init,
    :os,
    :persistent_term,
    :rand,
    :random
  ]

  # Elixir's applications a release ships - the others (Mix, ExUnit, IEx) are absent from
  # one, so a call to them fails at runtime anyway.
  @elixir_apps [:eex, :elixir, :logger]

  @doc """
  Validates that the compiled migration module given by its env and bytecode calls only
  its own functions and the standard library's functions that compute on the values they
  are given. No remote call, function capture or struct literal names another function or
  module, no call goes to a module chosen at runtime, and no field access is left that
  could call one. The module compiles through no parse transform, and neither requires a
  module outside the standard libraries nor used one while it compiled, `Hologram.Migration`
  and the definitions it imports aside, which its `use` requires. Returns :ok, or raises
  Hologram.CompileError naming each refused reference, with its line where it has one.

  Reads the module's debug info, which `use Hologram.Migration` keeps for every migration
  module.
  """
  @spec validate!(Macro.Env.t(), binary) :: :ok
  def validate!(env, bytecode) do
    file = Path.relative_to_cwd(env.file)

    code_references =
      bytecode
      |> definitions!(env.module, file)
      |> collect_references(env.module)

    # A module the code names already has a line to show, which says more.
    code_modules =
      MapSet.new(code_references, fn
        {:call, module, _fun, _arity, _line} -> module
        {:struct, module, _line} -> module
        {_dynamic_field_or_receive, _line} -> nil
      end)

    used_modules = compile_time_modules(env)

    compile_time_references =
      env.requires
      |> Enum.concat(used_modules)
      |> Enum.uniq()
      |> Enum.reject(
        &(&1 in [Hologram.Migration, Definitions, env.module] or
            (MapSet.member?(code_modules, &1) and &1 not in @environment_modules))
      )
      |> refused_compile_time_modules(used_modules)

    refused =
      code_references
      |> Enum.reject(&allowed?(&1, env.module))
      |> Enum.concat(compile_time_references)
      |> Enum.concat(transforms(bytecode))
      |> Enum.map(&refusal_line(&1, file))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(fn {_line, text} -> text end)

    if refused != [] do
      raise Hologram.CompileError, message: refusal_message(refused, compile_time_references)
    end

    :ok
  end

  defp allowed?({:call, migration, _fun, _arity, _line}, migration), do: true

  defp allowed?({:call, :erlang, fun, arity, _line}, _migration) do
    fun in @erlang_functions or {fun, arity} in @erlang_functions
  end

  defp allowed?({:call, module, fun, arity, _line}, _migration) do
    case @allowed_functions do
      %{^module => :all} -> true
      %{^module => funs} -> fun in funs or {fun, arity} in funs
      _other -> exception_function?(module, fun, arity)
    end
  end

  defp allowed?({:struct, migration, _line}, migration), do: true

  # The data form of a computed backfill, which `backfill:` writes into the op. It has no
  # functions the migration calls, and the pinned code in its fields is walked like any other.
  defp allowed?({:struct, Value, _line}, _migration), do: true

  defp allowed?({:struct, module, _line}, _migration) do
    module not in @refused_structs and
      (Map.has_key?(@allowed_functions, module) or exception?(module))
  end

  defp allowed?({:dynamic, _line}, _migration), do: false

  defp allowed?({:field, _line}, _migration), do: false

  defp allowed?({:receive, _line}, _migration), do: false

  # Function.capture/3 and apply/2,3 compile into these.
  defp call_name(:erlang, :apply, arity), do: "apply/#{arity}"

  defp call_name(:erlang, :make_fun, 3), do: "Function.capture/3"

  defp call_name(module, fun, arity), do: Exception.format_mfa(module, fun, arity)

  defp collect_references(definitions, migration) do
    definitions
    |> Enum.reduce([], fn {_name_arity, _kind, line, [args, guards, body]}, acc ->
      walk([args, body], line, guard_references(guards, line) ++ acc)
    end)
    |> walk_struct_fields(migration)
  end

  # A field read in a guard compiles into a map read, which never calls a module.
  defp guard_references(guards, line) do
    guards
    |> walk(line, [])
    |> Enum.reject(&match?({:field, _line}, &1))
  end

  # An Elixir exception is raised with its exception/1 and read with its message/1.
  defp exception?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :exception, 1) and
      :application.get_application(module) == {:ok, :elixir}
  end

  defp exception_function?(module, fun, arity) do
    {fun, arity} in [exception: 1, message: 1] and exception?(module)
  end

  # Walks expanded code, carrying the nearest line. A variable's context and a node's
  # metadata name modules too, and are not entered.
  defp walk(ast, line, acc)

  # A capture is taken whole - its call would otherwise read as one with no arguments.
  defp walk(
         {:&, _meta, [{:/, _slash_meta, [{{:., meta, [module, fun]}, _call_meta, []}, arity]}]},
         line,
         acc
       )
       when is_atom(fun) and is_integer(arity) do
    line = line(meta, line)
    remote_reference(module, fun, arity, line, acc)
  end

  # Field access the rewrite did not reach, which calls a function when the value is a
  # module, or a call with parentheses on a value.
  defp walk({{:., _meta, [receiver, fun]}, call_meta, []}, line, acc)
       when not is_atom(receiver) and is_atom(fun) do
    line = line(call_meta, line)
    reference = if call_meta[:no_parens], do: {:field, line}, else: {:dynamic, line}

    walk(receiver, line, [reference | acc])
  end

  defp walk({{:., meta, [module, fun]}, _call_meta, args}, line, acc)
       when is_atom(fun) and is_list(args) do
    line = line(meta, line)
    walk(args, line, remote_reference(module, fun, length(args), line, acc))
  end

  # Its fields are walked once the struct is known to be allowed: a refused one's hold its
  # defaults, and the struct says it all.
  defp walk({:%, meta, [module, fields]}, line, acc) when is_atom(module) do
    line = line(meta, line)
    [{:struct, module, line, fields} | acc]
  end

  # A pattern binding a struct's module, %module{}.
  defp walk({:%, meta, [module, fields]}, line, acc) do
    line = line(meta, line)
    walk(fields, line, walk(module, line, acc))
  end

  # A struct held as a value, like an attribute's, compiles into a map with its
  # __struct__.
  defp walk({:%{}, meta, fields} = map, line, acc) when is_list(fields) do
    case List.keyfind(fields, :__struct__, 0) do
      {:__struct__, module} when is_atom(module) ->
        walk(
          {:%, meta, [module, {:%{}, meta, List.keydelete(fields, :__struct__, 0)}]},
          line,
          acc
        )

      _no_struct ->
        walk_node(map, line, acc)
    end
  end

  # A message from the mailbox is whatever another process sent.
  defp walk({:receive, meta, args}, line, acc) when is_list(args) do
    [{:receive, line(meta, line)} | acc]
  end

  defp walk({_name, _meta, context}, _line, acc) when is_atom(context), do: acc

  defp walk({_form, meta, _args} = node, line, acc) when is_list(meta) do
    walk_node(node, line, acc)
  end

  defp walk({left, right}, line, acc), do: walk(right, line, walk(left, line, acc))

  defp walk(list, line, acc) when is_list(list) do
    Enum.reduce(list, acc, &walk(&1, line, &2))
  end

  defp walk(_literal, _line, acc), do: acc

  defp walk_struct_fields(references, migration) do
    Enum.flat_map(references, fn
      {:struct, module, line, fields} ->
        reference = {:struct, module, line}

        if allowed?(reference, migration) do
          field_references = walk(fields, line, [])
          [reference | walk_struct_fields(field_references, migration)]
        else
          [reference]
        end

      reference ->
        [reference]
    end)
  end

  defp walk_node({form, meta, args}, line, acc) do
    line = line(meta, line)
    walk(args, line, walk(form, line, acc))
  end

  # The modules the compiler recorded the migration using while it compiled - for a call or
  # a macro - and those whose exports it depends on, like a struct's. Kernel.LexicalTracker is
  # Elixir's internal record of them, alive until the file is compiled; a test pins its shape,
  # so an Elixir release that changes it fails Hologram's own suite rather than turning the
  # check off quietly.
  defp compile_time_modules(env) do
    with tracker when is_pid(tracker) <- env.lexical_tracker,
         true <- Process.alive?(tracker),
         true <- function_exported?(Kernel.LexicalTracker, :references, 1),
         references when is_tuple(references) and tuple_size(references) >= 2 <-
           Kernel.LexicalTracker.references(tracker) do
      elem(references, 0) ++ elem(references, 1)
    else
      _unavailable -> []
    end
  end

  defp definitions!(bytecode, module, file) do
    with {:ok, {_module, [debug_info: {:debug_info_v1, backend, data}]}} <-
           :beam_lib.chunks(bytecode, [:debug_info]),
         {:ok, %{definitions: definitions}} <- backend.debug_info(:elixir_v1, module, data, []) do
      # A clause is a 4-tuple, which the AST walk would not enter, so its parts are taken out.
      Enum.flat_map(definitions, &definition_clauses/1)
    else
      # Unreachable while use Hologram.Migration sets @compile {:debug_info, true}, which
      # wins over the project's option and the module's own.
      _error ->
        raise Hologram.CompileError,
          message: "#{file} has no debug info, so the calls it makes cannot be checked"
    end
  end

  defp definition_clauses({name_arity, kind, _meta, clauses}) do
    Enum.map(clauses, fn {clause_meta, args, guards, body} ->
      {name_arity, kind, clause_meta[:line], [args, guards, body]}
    end)
  end

  defp elixir_app_module?(module) do
    case :application.get_application(module) do
      {:ok, app} -> app in @elixir_apps
      :undefined -> false
    end
  end

  defp expand_dir(dir) do
    dir
    |> to_string()
    |> Path.expand()
  end

  # Generated code carries line 0, which says nothing.
  defp line(meta, line) do
    case Keyword.get(meta, :line) do
      meta_line when is_integer(meta_line) and meta_line > 0 -> meta_line
      _no_line -> line
    end
  end

  defp location(file, nil), do: file

  defp location(file, line), do: "#{file}:#{line}"

  # Each refused module is judged once - :environment for a standard module the module body
  # used that reads the environment (one only required, as Elixir requires Application in
  # every module, reads nothing), :missing for a module the code path does not hold (yet: in
  # a fresh build, an app module the compiler has not reached is not there), :outside for
  # the rest.
  # A module defined in the migration's file besides it - a nested defmodule, a defimpl - is
  # compiled through :elixir_module, and its code is not checked here.
  defp refused_compile_time_modules(modules, used_modules) do
    standard_dirs = standard_library_dirs()

    modules
    |> Enum.flat_map(fn
      :elixir_module ->
        [:other_module]

      module ->
        cond do
          module in @environment_modules and module in used_modules ->
            [{:compile_time, module, :environment}]

          standing(module, standard_dirs) == :standard ->
            []

          true ->
            [{:compile_time, module, standing(module, standard_dirs)}]
        end
    end)
    |> Enum.uniq()
  end

  defp refusal_line({:call, module, fun, arity, line}, file) do
    {line || 0, "  #{location(file, line)} - calls #{call_name(module, fun, arity)}"}
  end

  defp refusal_line({:struct, module, line}, file) do
    {line || 0, "  #{location(file, line)} - builds a %#{inspect(module)}{} struct"}
  end

  defp refusal_line(:other_module, file) do
    {0, "  #{file} - defines a module besides the migration"}
  end

  defp refusal_line({:receive, line}, file) do
    {line || 0, "  #{location(file, line)} - receives a message"}
  end

  defp refusal_line({:field, line}, file) do
    {line || 0,
     "  #{location(file, line)} - reads a field outside the definitions use " <>
       "Hologram.Migration imports, where it could call a module's function"}
  end

  defp refusal_line({:transform, module}, file) do
    {0, "  #{file} - compiles through the transform #{inspect(module)}"}
  end

  defp refusal_line({:dynamic, line}, file) do
    {line || 0, "  #{location(file, line)} - calls a function of a module known only at runtime"}
  end

  defp refusal_line({:compile_time, module, reason}, file) do
    suffix =
      case reason do
        :environment -> ", which can read the environment, the clock or a random source"
        :missing -> ", which is not compiled yet or cannot be found"
        :outside -> ""
      end

    {0, "  #{file} - uses #{inspect(module)} at compile time#{suffix}"}
  end

  # The hint says how to name a module without using it at compile time.
  defp module_hint?({:compile_time, _module, reason}), do: reason != :environment

  defp module_hint?(_reference), do: false

  defp refusal_message(lines, compile_time_references) do
    hint =
      if Enum.any?(compile_time_references, &module_hint?/1),
        do:
          "\nAn op reading an attribute that holds a module uses the module at compile " <>
            "time - if that is the case here, write the module in the op itself.",
        else: ""

    "a migration may call only its own functions and the standard library's functions " <>
      "that compute on the values they are given, like most of Kernel, String, Enum, Map " <>
      "and Date - what it does to rows must never change after it is applied, and the " <>
      "app's, its dependencies' and Hologram's modules change with them, as do a module " <>
      "chosen at runtime, the clock, the environment and random sources:\n" <>
      Enum.join(lines, "\n") <> hint
  end

  defp remote_reference(module, fun, arity, line, acc) when is_atom(module) do
    [{:call, module, fun, arity, line} | acc]
  end

  defp remote_reference(receiver, _fun, _arity, line, acc) do
    walk(receiver, line, [{:dynamic, line} | acc])
  end

  # An Erlang parse or core transform rewrites the code after the debug info this reads.
  defp transforms(bytecode) do
    case :beam_lib.chunks(bytecode, [:compile_info]) do
      {:ok, {_module, [compile_info: info]}} ->
        for {kind, module} <- Keyword.get(info, :options, []),
            kind in [:core_transform, :parse_transform],
            do: {:transform, module}

      _no_info ->
        []
    end
  end

  defp standard_library_dirs do
    elixir_dirs =
      Enum.flat_map(@elixir_apps, fn app ->
        case :code.lib_dir(app) do
          dir when is_list(dir) -> [expand_dir(dir)]
          {:error, :bad_name} -> []
        end
      end)

    [expand_dir(:code.root_dir()) | elixir_dirs]
  end

  # An Elixir protocol is judged by its application rather than its path: once Mix has
  # consolidated protocols, a VM that is already running - a code reloader, an IEx
  # recompile, a test run - loads them from the project's build dir.
  defp standing(module, standard_dirs) do
    case :code.which(module) do
      :preloaded ->
        :standard

      path when is_list(path) ->
        expanded_path = expand_dir(path)

        if elixir_app_module?(module) or
             Enum.any?(standard_dirs, &String.starts_with?(expanded_path, &1 <> "/")) do
          :standard
        else
          :outside
        end

      :non_existing ->
        :missing

      _cover_compiled ->
        :outside
    end
  end
end
