defmodule Hologram.Migration.CallCheck do
  @moduledoc false

  # What a migration does to a row must never change after it is applied, so its code
  # may call only what does not change with the app: its own functions and the standard
  # library's modules that work on values. A call to one of the app's modules, a
  # dependency's or Hologram's would change whenever they do, and so would a call to a
  # module chosen at runtime - through apply/3, Function.capture/3, mod.fun() or a function
  # that evaluates code. The allowed modules are listed rather than the dispatching ones
  # refused, so a dispatching function nobody thought of is refused too.
  #
  # A standard function can call a module given to it as a value, too: Enum.sort/2 a
  # sorter's compare/2, Date.new/4 a calendar's functions, to_string/1 the String.Chars
  # implementation of a map whose __struct__ names the module. So the code may hold no
  # module outside the allowed ones - an op's entity types aside, in the fields that name
  # them - may not build an atom from a string, which could spell one, and may not read its
  # own ops back, which would hand it those entity types. A macro's code is checked like a
  # function's - one the migration itself calls has run by the time the check does, but the
  # build still fails. An Erlang parse transform is refused, as it rewrites the code after
  # the debug info read here.
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
  # Known blind spots: m.fun without parentheses compiles like the field access row.name,
  # which stays allowed, though it calls the function when m holds a module (Elixir warns
  # when it runs), and raising a module held in a variable calls its exception/1; an
  # Erlang module of the app, its name a plain atom, passes as a value; a module-body call
  # to a module chosen at runtime names no module; a module-body call to Hologram.Migration
  # cannot be told apart from the use that requires it; and a call that reads the
  # environment, the clock or a random source passes, though its value can differ per build
  # or boot - DateTime.now/1 reads the time zone database the app configured.

  # Modules whose every function works on the values it is given, and a struct of which a
  # migration may build. The protocols dispatch on the value's type, and a migration holds
  # no value of the app's types: it builds none and calls nothing that returns one.
  @allowed_modules [
    Access,
    Atom,
    Base,
    Bitwise,
    Calendar,
    Calendar.ISO,
    Collectable,
    Date,
    Date.Range,
    DateTime,
    Duration,
    Enum,
    Enumerable,
    Exception,
    Float,
    Function,
    IO,
    Inspect,
    Integer,
    JSON,
    Kernel,
    Keyword,
    List,
    List.Chars,
    Map,
    MapSet,
    NaiveDateTime,
    Range,
    Regex,
    Stream,
    String,
    String.Chars,
    Time,
    Tuple,
    URI,
    Version,
    Version.Requirement,
    :base64,
    :binary,
    :calendar,
    # The quote machinery a defguard or a defmacro with unquote compiles into.
    :elixir_quote,
    :lists,
    :maps,
    :math,
    :re,
    :string,
    :ordsets,
    :proplists,
    :queue,
    :sets,
    :unicode,
    :uri_string
  ]

  # Functions of the allowed modules that call a module given as a value, reach code or
  # processes outside the migration, return a module the app chose, or build an atom from a
  # string.
  @refused_functions %{
    Calendar => [:get_time_zone_database, :put_time_zone_database],
    Collectable => [:__protocol__, :impl_for, :impl_for!],
    Enumerable => [:__protocol__, :impl_for, :impl_for!],
    Function => [:capture],
    # Those reading input, and those writing to a device given - any registered process.
    IO => [
      :binread,
      :binstream,
      :getn,
      :gets,
      :read,
      :stream,
      binwrite: 2,
      inspect: 3,
      puts: 2,
      write: 2
    ],
    Inspect => [:__protocol__, :impl_for, :impl_for!],
    Kernel => [
      :apply,
      :function_exported?,
      :macro_exported?,
      :send,
      :spawn,
      :spawn_link,
      :spawn_monitor,
      :struct,
      :struct!
    ],
    List => [:to_atom, :to_existing_atom],
    List.Chars => [:__protocol__, :impl_for, :impl_for!],
    String => [:to_atom, :to_existing_atom],
    String.Chars => [:__protocol__, :impl_for, :impl_for!]
  }

  # Single functions of modules not allowed whole: Logger's logging - not its
  # configuration, which installs the app's handlers and translators - raise/1 with a
  # message held in a variable, the guard check of a defguard, Macro's name conversions,
  # and the hashing and formatting of :crypto and :io_lib, whose other functions load
  # engines or read atoms from text.
  @allowed_functions %{
    :crypto => [:hash, :hash_final, :hash_init, :hash_update, :mac, :strong_rand_bytes],
    :io_lib => [:format, :fwrite],
    Kernel.Utils => [:raise],
    Logger => [:__do_log__, :__should_log__, :bare_log, :flush, :level, :metadata],
    Macro => [:camelize, :escape, :to_string, :underscore, :var],
    Macro.Env => [:in_guard?]
  }

  # The :erlang functions that compute on values only - the ones Kernel compiles into, and
  # their like. The rest of :erlang reaches processes, ports, code loading and dispatch.
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
    :exit,
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
    :list_to_binary,
    :list_to_bitstring,
    :list_to_float,
    :list_to_integer,
    :list_to_tuple,
    :make_tuple,
    :map_get,
    :make_ref,
    :md5,
    :map_size,
    :max,
    :min,
    :node,
    :not,
    :or,
    :orelse,
    :phash2,
    :raise,
    :rem,
    :round,
    :self,
    :setelement,
    :split_binary,
    :term_to_binary,
    :throw,
    :tl,
    :trunc,
    :tuple_size,
    :tuple_to_list,
    :unique_integer,
    :xor
  ]

  # exit/2 signals another process.
  @refused_erlang_calls [exit: 2]

  # The op map fields that name entity types and roles, and those of an op's opts,
  # changes and resolve! payload.
  @entity_fields [:entity, :from, :role, :to, :type]

  @entity_option_fields [:extends, :type]

  @entity_payload_fields [:added, :deleted, :from, :to]

  # Elixir's applications a release ships - the others (Mix, ExUnit, IEx) are absent from
  # one, so a call to them fails at runtime anyway.
  @elixir_apps [:eex, :elixir, :logger]

  @doc """
  Validates that the compiled migration module given by its env and bytecode calls only
  its own functions and the standard library's modules that work on values. No remote
  call, function capture or struct literal names another module, no call goes to a module
  chosen at runtime, and the code holds no other module but the entity types and roles its
  ops name, builds no atom from a string and does not read its own ops back. The module
  compiles through no parse transform, and neither requires a module outside the standard
  libraries nor used one while it compiled, `Hologram.Migration` aside, which its `use`
  requires. Returns :ok, or raises Hologram.CompileError naming each refused reference,
  with its line where it has one.

  Reads the module's debug info, which `use Hologram.Migration` keeps for every migration
  module.
  """
  @spec validate!(Macro.Env.t(), binary) :: :ok
  def validate!(env, bytecode) do
    file = Path.relative_to_cwd(env.file)

    code_references =
      bytecode
      |> definitions!(env.module, file)
      |> collect_references()

    # A module the code names already has a line to show, which says more.
    code_modules =
      MapSet.new(code_references, fn
        {:call, module, _fun, _arity, _line} -> module
        {:struct, module, _line} -> module
        {:module, module, _line} -> module
        {_dynamic_or_own_ops, _line} -> nil
      end)

    compile_time_references =
      env.requires
      |> Enum.concat(compile_time_modules(env))
      |> Enum.uniq()
      |> Enum.reject(
        &(&1 in [Hologram.Migration, env.module] or MapSet.member?(code_modules, &1))
      )
      |> refused_compile_time_modules()

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

  # The ops it reads back would hand it the modules they name.
  defp allowed?({:call, migration, :__hologram_migration__, _arity, _line}, migration) do
    false
  end

  defp allowed?({:call, migration, _fun, _arity, _line}, migration), do: true

  defp allowed?({:call, :erlang, fun, arity, _line}, _migration) do
    fun in @erlang_functions and {fun, arity} not in @refused_erlang_calls
  end

  defp allowed?({:call, module, fun, arity, _line}, _migration) do
    case @allowed_functions do
      %{^module => funs} ->
        fun in funs

      _other ->
        refused = Map.get(@refused_functions, module, [])
        allowed_module?(module) and fun not in refused and {fun, arity} not in refused
    end
  end

  defp allowed?({:struct, module, _line}, _migration), do: allowed_module?(module)

  defp allowed?({:module, migration, _line}, migration), do: true

  defp allowed?({:module, module, _line}, _migration) do
    allowed_module?(module) or Map.has_key?(@allowed_functions, module)
  end

  defp allowed?({:own_ops, _line}, _migration), do: false

  defp allowed?({:dynamic, _line}, _migration), do: false

  # An Elixir exception is raised with its exception/1 and read with its message/1.
  defp allowed_module?(module) do
    module in @allowed_modules or
      (Code.ensure_loaded?(module) and function_exported?(module, :exception, 1) and
         :application.get_application(module) == {:ok, :elixir})
  end

  # Function.capture/3 and apply/2,3 compile into these.
  defp call_name(:erlang, :apply, arity), do: "apply/#{arity}"

  defp call_name(:erlang, :make_fun, 3), do: "Function.capture/3"

  defp call_name(module, fun, arity), do: Exception.format_mfa(module, fun, arity)

  # The generated __hologram_migration__/0 holds the op maps, whose entity type fields are
  # where a migration names app modules; anywhere else, a module name is refused.
  defp collect_references(definitions) do
    Enum.reduce(definitions, [], fn
      {{:__hologram_migration__, 0}, :def, _line, [[], [], body]}, acc ->
        migration_references(body, acc)

      {_name_arity, _kind, line, parts}, acc ->
        walk(parts, line, acc)
    end)
  end

  defp migration_references(
         {:%{}, _meta,
          [
            version: _version,
            path: _path,
            ops: {{:., _dot_meta, [List, :flatten]}, _call_meta, [ops]}
          ]},
         acc
       ) do
    walk_ops(ops, acc)
  end

  defp migration_references(body, acc), do: walk(body, nil, acc)

  defp walk_ops(ops, acc) when is_list(ops), do: Enum.reduce(ops, acc, &walk_ops/2)

  defp walk_ops({:%{}, _meta, [{:op, _op} | _rest] = fields}, acc) do
    line = Keyword.get(fields, :line)

    Enum.reduce(fields, acc, fn
      {key, value}, acc when key in @entity_fields ->
        walk_entity_types(value, line, acc)

      {key, value}, acc when key in [:changes, :opts] ->
        walk_fields(value, @entity_option_fields, line, acc)

      {:payload, payload}, acc ->
        walk_fields(payload, @entity_payload_fields, line, acc)

      {_key, value}, acc ->
        walk(value, line, acc)
    end)
  end

  defp walk_ops(other, acc), do: walk(other, nil, acc)

  defp walk_fields(fields, entity_fields, line, acc) when is_list(fields) do
    Enum.reduce(fields, acc, fn
      {key, value}, acc when is_atom(key) ->
        if key in entity_fields,
          do: walk_entity_types(value, line, acc),
          else: walk(value, line, acc)

      other, acc ->
        walk(other, line, acc)
    end)
  end

  defp walk_fields(other, _entity_fields, line, acc), do: walk(other, line, acc)

  defp walk_entity_types(value, line, acc) do
    if is_atom(value) or (is_list(value) and Enum.all?(value, &is_atom/1)),
      do: acc,
      else: walk(value, line, acc)
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

  # Field access, as on a map - Elixir compiles m.fun without parentheses the same.
  defp walk({{:., _meta, [receiver, fun]}, call_meta, []}, line, acc)
       when not is_atom(receiver) and is_atom(fun) do
    line = line(call_meta, line)

    acc =
      cond do
        fun == :__hologram_migration__ -> [{:own_ops, line} | acc]
        call_meta[:no_parens] -> acc
        true -> [{:dynamic, line} | acc]
      end

    walk(receiver, line, acc)
  end

  defp walk({{:., meta, [module, fun]}, _call_meta, args}, line, acc)
       when is_atom(fun) and is_list(args) do
    line = line(meta, line)
    walk(args, line, remote_reference(module, fun, length(args), line, acc))
  end

  # A refused struct's fields are left out: they hold its defaults, the struct says it all.
  defp walk({:%, meta, [module, fields]}, line, acc) when is_atom(module) do
    line = line(meta, line)
    acc = [{:struct, module, line} | acc]

    if allowed_module?(module), do: walk(fields, line, acc), else: acc
  end

  # A pattern binding a struct's module, %module{} - the module can only be an allowed one,
  # the migration building no other struct.
  defp walk({:%, meta, [module, fields]}, line, acc) do
    line = line(meta, line)
    walk(fields, line, walk(module, line, acc))
  end

  # A struct held as a value, like an attribute's, compiles into a map with its
  # __struct__ - and so does one forged to reach a module's protocol implementations.
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

  # A local call or capture of the ops function, which would hand the code the modules
  # the ops name.
  defp walk({:__hologram_migration__, meta, _args}, line, acc) do
    [{:own_ops, line(meta, line)} | acc]
  end

  defp walk({_name, _meta, context}, _line, acc) when is_atom(context), do: acc

  defp walk({_form, meta, _args} = node, line, acc) when is_list(meta) do
    walk_node(node, line, acc)
  end

  defp walk({left, right}, line, acc), do: walk(right, line, walk(left, line, acc))

  defp walk(list, line, acc) when is_list(list) do
    Enum.reduce(list, acc, &walk(&1, line, &2))
  end

  defp walk(atom, line, acc) when is_atom(atom) do
    name = Atom.to_string(atom)

    if String.starts_with?(name, "Elixir."),
      do: [{:module, atom, line} | acc],
      else: acc
  end

  defp walk(_literal, _line, acc), do: acc

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

  # Each refused module is judged once - :missing for a module the code path does not hold
  # (yet: in a fresh build, an app module the compiler has not reached is not there),
  # :outside for the rest.
  # A module defined in the migration's file besides it - a nested defmodule, a defimpl - is
  # compiled through these, and its code is not checked here.
  defp refused_compile_time_modules(modules) do
    standard_dirs = standard_library_dirs()

    modules
    |> Enum.flat_map(fn
      module when module in [:elixir_module, Protocol] ->
        [:other_module]

      module ->
        case standing(module, standard_dirs) do
          :standard -> []
          reason -> [{:compile_time, module, reason}]
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

  defp refusal_line({:module, module, line}, file) do
    {line || 0, "  #{location(file, line)} - holds the module #{inspect(module)}"}
  end

  defp refusal_line(:other_module, file) do
    {0, "  #{file} - defines a module besides the migration"}
  end

  defp refusal_line({:own_ops, line}, file) do
    {line || 0, "  #{location(file, line)} - reads the migration's own ops"}
  end

  defp refusal_line({:transform, module}, file) do
    {0, "  #{file} - compiles through the transform #{inspect(module)}"}
  end

  defp refusal_line({:dynamic, line}, file) do
    {line || 0, "  #{location(file, line)} - calls a function of a module known only at runtime"}
  end

  defp refusal_line({:compile_time, module, reason}, file) do
    suffix = if reason == :missing, do: ", which is not compiled yet or cannot be found", else: ""

    {0, "  #{file} - uses #{inspect(module)} at compile time#{suffix}"}
  end

  defp refusal_message(lines, compile_time_references) do
    hint =
      if Enum.any?(compile_time_references, &match?({:compile_time, _module, _reason}, &1)),
        do:
          "\nAn op reading an attribute that holds a module uses the module at compile " <>
            "time - if that is the case here, write the module in the op itself.",
        else: ""

    "a migration may call only its own functions and the standard library's modules that " <>
      "work on values, like Kernel, String, Enum, Map and Date, and may hold no other module " <>
      "than the entity types and roles its ops name - what it does to rows must never " <>
      "change after it is applied, and the app's, its dependencies' and Hologram's modules " <>
      "change with them, as does a module chosen at runtime:\n" <>
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
