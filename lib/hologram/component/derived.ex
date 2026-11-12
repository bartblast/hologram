defmodule Hologram.Component.Derived do
  @moduledoc false

  # The derived fields of a component or a page: declared by derived/3, checked once the module body
  # has run, reflected as __derived__/0 with a public function per field holding its body, and
  # computed by the server render (compute/6), which the client render mirrors.
  #
  # A field's function is hoisted into a def of the module rather than kept as a closure, so its body
  # is ordinary module code: called on the server, walked by the build through IR, and transpiled for
  # the client, which the call graph reaches through the capture __derived__/0 holds.

  alias Hologram.Compiler.AST
  alias Hologram.Component.NotComputed
  alias Hologram.Query
  alias Hologram.Query.Stage
  alias Hologram.Reflection

  # The query macros whose arguments after the source are query vocabulary, where a bare name is the
  # queried row's and only a pinned expression reads the surrounding Elixir.
  @query_macros [filter: 2, include: 2, paginate: 2, skip: 2, sort: 2, take: 2]

  @doc """
  Computes the given derived field entries of the given component or page module, in the order
  given, and returns the given computed values with theirs added.

  Each function is given its arguments by name: the props (params on a page), then the state, then
  the values computed so far. The result of a field the build registered as a query, which the
  `:registered_query?` option answers for a field's name, is normalized, checked against the
  field's type and handed to the `:run_query` option, a function taking the field's name, its
  arguments and the term, whose result is the field's value. Any other result is checked against
  the field's type.

  With the `:stateless` option a component renders without a cid, so it has no state to read.

  Raises Hologram.MisuseError when an argument has no value, when a result doesn't match the field's
  type, when a field the build didn't register returns a query, and Hologram.StateError when a
  stateless component's field reads state.

  WARNING: must match the client renderer's #computeDerived (renderer.mjs), messages included - but
  for a value each tier spells with its own inspect, which spell structs and the key order of maps
  differently.
  """
  @spec compute([map], module, map, map, map, keyword) :: map
  def compute(entries, module, props, state, computed, opts) do
    Enum.reduce(entries, computed, fn entry, acc ->
      args = Enum.map(entry.args, &argument!(&1, entry, module, props, state, acc, opts))

      value =
        entry.function
        |> apply(args)
        |> computed_value!(entry, module, args, opts)

      Map.put(acc, entry.name, value)
    end)
  end

  @doc """
  Returns the AST of code that accumulates the given derived field declaration in __derived__
  module attribute, after checking the shape of its function at the declaration's line: a capture of
  a zero-arity function stands for the function calling it, and the function has one clause, no
  guard and arguments that are distinct bare names.
  """
  @spec declaration(any, Macro.t(), Macro.t(), Macro.Env.t()) :: AST.t()
  def declaration(name, type, definition, env) do
    if not is_atom(name) do
      raise Hologram.CompileError,
        message:
          "the name of derived field #{Macro.to_string(name)} in #{inspect(env.module)} must be an atom",
        file: env.file,
        line: env.line
    end

    definition = Hologram.Derived.function(name, definition, env)

    Hologram.Derived.validate_function!(name, definition, env)

    {:fn, _meta, [{:->, _arrow_meta, [args, body]}]} = definition
    arg_names = Enum.map(args, fn {arg_name, _meta, _context} -> arg_name end)

    body_at_line =
      env
      |> imports_at_line()
      |> Enum.concat([resolve_at_line(body, env)])
      |> then(&{:__block__, [], &1})

    declaration = {name, args, arg_names, body_at_line, env.line}

    quote do
      Module.put_attribute(
        __MODULE__,
        :__derived__,
        {unquote(Macro.escape(declaration, unquote: true)), unquote(type)}
      )
    end
  end

  @doc """
  Returns what the derived fields given hold while `init` runs: a placeholder each, since they read
  state, which `init` sets.
  """
  @spec not_computed([map]) :: %{atom => NotComputed.t()}
  def not_computed(entries) do
    Map.new(entries, &{&1.name, %NotComputed{field: &1.name}})
  end

  @doc """
  Returns the AST of the given component or page module's derived field reflection: a public
  function per field holding its body, named `__derived_<name>__`, and `__derived__/0` listing the
  fields in the order they can be computed - each after every field it reads, the declaration order
  deciding the rest. Each entry names the field, its type, the names its function's arguments bind,
  a capture of that function and whether the field reads state, directly or through another field.

  Raises Hologram.CompileError, located at the declaration, when a field's name is taken by a prop
  (a param on a page), a state entry, the cid or another derived field, when its function's head
  names what is none of the module's props (params), state entries and other derived fields, or the
  field itself, when its body reads a field its head doesn't name, and when fields read each other
  in a cycle.
  """
  @spec reflection(Macro.Env.t()) :: AST.t()
  def reflection(env) do
    module = env.module

    declarations =
      module
      |> Module.get_attribute(:__derived__)
      |> Enum.reverse()

    inputs = inputs(module)

    validate_names!(declarations, inputs, env)

    fields = Map.merge(inputs, Map.new(declarations, &{declaration_name(&1), "derived field"}))

    Enum.each(declarations, &validate_head!(&1, fields, env))
    Enum.each(declarations, &validate_body!(&1, fields, env))

    ordered = order!(declarations, env)
    reads_state = reads_state(ordered, inputs)

    entries =
      Enum.map(ordered, fn {{name, _args, arg_names, _body, _line}, type} ->
        function_name = function_name(name)
        arity = length(arg_names)

        quote do
          %{
            args: unquote(arg_names),
            function: &(__MODULE__.unquote(function_name) / unquote(arity)),
            name: unquote(name),
            reads_state: unquote(MapSet.member?(reads_state, name)),
            type: unquote(Macro.escape(type))
          }
        end
      end)

    functions =
      Enum.map(declarations, fn {{name, args, _arg_names, body, line}, _type} ->
        # At the declaration's line, which is where the build's refusals point.
        quote line: line do
          @doc false
          def unquote(function_name(name))(unquote_splicing(args)) do
            unquote(body)
          end
        end
      end)

    reflection_function =
      quote do
        @doc """
        Returns the list of derived field definitions for the compiled component or page, in the
        order they can be computed.
        """
        @spec __derived__() :: list(map)
        def __derived__, do: unquote(entries)
      end

    [reflection_function | functions]
  end

  @doc """
  Returns the AST of code that registers __derived__ module attribute.
  """
  @spec register_accumulator() :: AST.t()
  def register_accumulator do
    quote do
      Module.register_attribute(__MODULE__, :__derived__, accumulate: true)
    end
  end

  @doc """
  Returns the derived fields the given module computes before `init` and after it: the ones reading
  only props (params on a page) come before, the ones reading state after, since `init` is what
  sets the state they read.
  """
  @spec split_by_init([map]) :: {[map], [map]}
  def split_by_init(entries), do: Enum.split_with(entries, &(not &1.reads_state))

  @doc """
  Validates that the given state, returned by the given handler of the given module, holds no
  placeholder of a derived field not yet computed, as an entry or anywhere inside one - a state
  entry `init` copied it into would show it in every render after.

  Raises Hologram.StateError naming the field and the entry: of several, the smallest entry, and of
  several under it, the smallest field.
  """
  @spec validate_state_computed!(map, module, String.t()) :: :ok
  def validate_state_computed!(state, module, handler) do
    stored =
      state
      |> Enum.flat_map(fn {key, value} ->
        case placeholders_in(value, []) do
          [] -> []
          placeholders -> [{key, Enum.min_by(placeholders, & &1.field)}]
        end
      end)
      |> Enum.min_by(fn {key, _placeholder} -> key end, fn -> nil end)

    case stored do
      {key, %NotComputed{field: field}} ->
        raise Hologram.StateError,
          message:
            "#{handler} of #{Reflection.module_name(module)} stored derived field #{inspect(field)} in state #{inspect(key)} before it was computed - it reads state, so it's computed after init"

      nil ->
        :ok
    end
  end

  # The names an alias or require directive declares as aliases: the one as: gives, otherwise, for
  # an alias, the last segment of each module it names.
  defp aliased_names(directive, target, opts) do
    as =
      case opts do
        [options] when is_list(options) -> List.keyfind(options, :as, 0)
        _no_options -> nil
      end

    case as do
      {:as, {:__aliases__, _meta, [name]}} -> [name]
      _no_as when directive == :alias -> last_segments(target)
      _no_as -> []
    end
  end

  defp argument!(name, entry, module, props, state, computed, opts) do
    cond do
      Map.has_key?(props, name) ->
        Map.fetch!(props, name)

      state_name?(module, name) and opts[:stateless] ->
        raise Hologram.StateError,
          message:
            "derived field #{inspect(entry.name)} in #{Reflection.module_name(module)} reads state #{inspect(name)}, which a component rendered without a cid doesn't have - give it a cid"

      Map.has_key?(state, name) ->
        Map.fetch!(state, name)

      Map.has_key?(computed, name) ->
        Map.fetch!(computed, name)

      true ->
        raise Hologram.MisuseError,
          message:
            "derived field #{inspect(entry.name)} in #{Reflection.module_name(module)} reads #{inspect(name)}, which is not set - #{unset_hint(module, name)}"
    end
  end

  defp compile_error!(message, env, line) do
    raise Hologram.CompileError, message: message, file: env.file, line: line
  end

  defp computed_value!(value, entry, module, args, opts) do
    registered_query? = Keyword.fetch!(opts, :registered_query?)

    cond do
      registered_query?.(entry.name) ->
        term = Stage.normalize(value)

        validate_query_type!(term, entry, module)

        opts
        |> Keyword.fetch!(:run_query)
        |> apply([entry.name, args, term])

      query?(value) ->
        raise Hologram.MisuseError,
          message:
            "derived field #{inspect(entry.name)} in #{Reflection.module_name(module)} returned a query the build didn't register - a query is built in the derived field's own function or the builders it calls, not passed in as data"

      true ->
        validate_value_type!(value, entry, module)

        value
    end
  end

  defp declaration_name({{name, _args, _arg_names, _body, _line}, _type}), do: name

  # The name is a derived field's own, written in the module's source, so the atoms it makes are
  # bounded by the code itself.
  # sobelow_skip ["DOS.BinToAtom"]
  # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
  defp function_name(name), do: :"__derived_#{name}__"

  # The body is compiled into its def once the module body has run, when the module's imports can
  # be others than at the declaration, so the def starts with the ones in effect there - the
  # body's own imports come after them and override them, as Elixir scopes them. Kernel's, imported
  # by default, are left out. warn: false, since a def reads only some of what the module imports.
  defp imports_at_line(env) do
    (env.functions ++ env.macros)
    |> Enum.group_by(fn {module, _names} -> module end, fn {_module, names} -> names end)
    |> Enum.reject(fn {module, _names} -> module in [Kernel, Kernel.SpecialForms] end)
    |> Enum.sort()
    |> Enum.map(fn {module, names} ->
      only =
        names
        |> Enum.concat()
        |> Enum.sort()

      quote do
        import unquote(module), only: unquote(only), warn: false
      end
    end)
  end

  # The names a derived field's function can read besides other derived fields, each with how the
  # messages describe what holds it. A page's params stand where a component's props do.
  defp inputs(module) do
    {holders, holder} =
      if Module.defines?(module, {:__is_hologram_page__, 0}) do
        {Module.get_attribute(module, :__params__), "param"}
      else
        {Module.get_attribute(module, :__props__), "prop"}
      end

    state = Module.get_attribute(module, :__state__)

    holders
    |> Enum.map(fn {name, _type, _opts} -> {name, holder} end)
    |> Enum.concat(Enum.map(state, fn {name, _type, _opts} -> {name, "state entry"} end))
    |> Map.new()
  end

  defp last_segments({:__aliases__, _meta, segments}), do: [List.last(segments)]

  defp last_segments({{:., _dot_meta, [_base, :{}]}, _meta, targets}),
    do: Enum.flat_map(targets, &last_segments/1)

  defp last_segments(_target), do: []

  defp module_label(env), do: inspect(env.module)

  # A field comes after every field it reads, and of the fields free to come next the one declared
  # first does. Whatever is left once none is free reads a cycle or depends on one, so the cycle
  # reported is a strongly connected part of what is left - its fields in declaration order, at
  # the first one's line.
  defp order!(declarations, env) do
    names = Enum.map(declarations, &declaration_name/1)

    reads =
      Map.new(declarations, fn {{name, _args, arg_names, _body, _line}, _type} ->
        {name, Enum.filter(arg_names, &(&1 in names))}
      end)

    case order_step(declarations, reads, []) do
      {ordered, []} -> ordered
      {_ordered, left} -> raise_cycle!(left, reads, env)
    end
  end

  defp order_step([], _reads, ordered), do: {Enum.reverse(ordered), []}

  defp order_step(left, reads, ordered) do
    done = Enum.map(ordered, &declaration_name/1)

    case Enum.find(left, fn declaration ->
           reads
           |> Map.fetch!(declaration_name(declaration))
           |> Enum.all?(&(&1 in done))
         end) do
      nil -> {Enum.reverse(ordered), left}
      free -> order_step(List.delete(left, free), reads, [free | ordered])
    end
  end

  # A query term, or an entity type standing for every row of it.
  # Adds to the given list the placeholders the given value holds, itself or anywhere inside a map,
  # a list or a tuple (an improper list's tail too). Every one is gathered, so that the smallest
  # field can be named whatever order a map is walked in.
  defp placeholders_in(%NotComputed{} = placeholder, acc), do: [placeholder | acc]

  defp placeholders_in([head | tail], acc), do: placeholders_in(tail, placeholders_in(head, acc))

  defp placeholders_in(value, acc) when is_map(value) do
    value
    |> Map.to_list()
    |> placeholders_in(acc)
  end

  defp placeholders_in(value, acc) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> placeholders_in(acc)
  end

  defp placeholders_in(_value, acc), do: acc

  defp query?(value) do
    is_struct(value, Query) or (is_atom(value) and Reflection.entity?(value))
  end

  defp query_description(%Query{cardinality: :count, entity: entity}),
    do: "a count of #{inspect(entity)} rows"

  defp query_description(%Query{cardinality: :one, entity: entity}),
    do: "one #{inspect(entity)} row"

  defp query_description(%Query{entity: entity}), do: "a set of #{inspect(entity)} rows"

  # Whether the given call is one of the query macros, given the number of arguments a pipe leaves
  # out of it: called unqualified where Hologram.Query is imported, by the module or earlier in the
  # body, or through the module, an alias of it included.
  defp query_macro?({{:., _dot_meta, [module_ast, name]}, _meta, args}, piped, state)
       when is_list(args) do
    {name, length(args) + piped} in @query_macros and query_module?(module_ast, state)
  end

  defp query_macro?({name, _meta, args}, piped, state) when is_atom(name) and is_list(args) do
    arity = length(args) + piped

    {name, arity} in @query_macros and
      ({name, arity} in state.query_imports or
         match?(
           [{_kind, Hologram.Query} | _rest],
           Macro.Env.lookup_import(state.env, {name, arity})
         ))
  end

  defp query_macro?(_ast, _piped, _state), do: false

  # Whether a module inside a multi-alias's braces is Hologram.Query, told by its name, so that no
  # atom is made for a module the body only names.
  defp query_member?(base_module, segments) when is_atom(base_module) do
    Enum.join([base_module | segments], ".") == Atom.to_string(Hologram.Query)
  end

  defp query_member?(_base_module, _segments), do: false

  defp query_module?({:__aliases__, _meta, [alias_name]}, state) when is_atom(alias_name) do
    cond do
      alias_name in state.query_aliases -> true
      alias_name in state.body_aliases -> false
      true -> Macro.expand({:__aliases__, [], [alias_name]}, state.env) == Hologram.Query
    end
  end

  defp query_module?(module_ast, state), do: Macro.expand(module_ast, state.env) == Hologram.Query

  @spec raise_cycle!(list, %{atom => [atom]}, Macro.Env.t()) :: no_return
  defp raise_cycle!(left, reads, env) do
    cycles =
      reads
      |> Map.take(Enum.map(left, &declaration_name/1))
      |> Hologram.Derived.cycles()

    members =
      Enum.find_value(left, fn declaration ->
        Enum.find(cycles, &(declaration_name(declaration) in &1))
      end)

    [{{_name, _args, _arg_names, _body, line}, _type} | _rest] =
      cycle = Enum.filter(left, &(declaration_name(&1) in members))

    spelled = Enum.map_join(cycle, ", ", &inspect(declaration_name(&1)))

    compile_error!(
      "derived fields in #{module_label(env)} read each other in a cycle: #{spelled}",
      env,
      line
    )
  end

  # The fields whose function reads a state entry, directly or through a field that does - in the
  # order given, every field a field reads comes before it.
  defp reads_state(ordered, inputs) do
    Enum.reduce(ordered, MapSet.new(), fn {{name, _args, arg_names, _body, _line}, _type}, acc ->
      if Enum.any?(arg_names, &(Map.get(inputs, &1) == "state entry" or &1 in acc)) do
        MapSet.put(acc, name)
      else
        acc
      end
    end)
  end

  # The body is compiled into its def once the module body has run, so what a def at the declaration
  # would read there is read there: a module attribute's value, through an unquote fragment the
  # declaration's escape evaluates where it stands, and an alias the module has declared. An alias
  # the body declares itself is known only inside the body, so from the directive on, until the
  # end of the block or clause it stands in, as Elixir scopes it, a name it declares is left as
  # written - even one the module aliases too.
  defp resolve_at_line(body, env) do
    {resolved, _declared} = resolve_names(body, MapSet.new(), env)

    resolved
  end

  # Returns the given AST with the names resolved, and the names the body has declared once it has
  # run - the ones declared before it, and the ones it declares for what follows it in its block.
  defp resolve_names({:@, _meta, [{attribute, _attribute_meta, context}]}, declared, _env)
       when is_atom(attribute) and is_atom(context) do
    fragment =
      {:unquote, [],
       [
         quote do
           __MODULE__
           |> Module.get_attribute(unquote(attribute))
           |> Macro.escape()
         end
       ]}

    {fragment, declared}
  end

  defp resolve_names({:__aliases__, meta, [first | _rest] = segments} = ast, declared, env)
       when is_atom(first) do
    if MapSet.member?(declared, first) do
      {ast, declared}
    else
      case Macro.Env.expand_alias(env, meta, segments) do
        {:alias, module} -> {module, declared}
        :error -> {ast, declared}
      end
    end
  end

  # A directive's target is read with the names declared before it, and the names it declares
  # count from the next expression on. Its options and the members inside braces name no module
  # through an alias, so they are left as written.
  defp resolve_names({directive, meta, [target | opts]}, declared, env)
       when directive in [:alias, :require] do
    resolved_target =
      case target do
        {{:., dot_meta, [base, :{}]}, braces_meta, members} ->
          {resolved_base, _declared} = resolve_names(base, declared, env)
          {{:., dot_meta, [resolved_base, :{}]}, braces_meta, members}

        _single ->
          {resolved, _declared} = resolve_names(target, declared, env)
          resolved
      end

    names =
      directive
      |> aliased_names(target, opts)
      |> MapSet.new()

    {{directive, meta, [resolved_target | opts]}, MapSet.union(declared, names)}
  end

  defp resolve_names({:__block__, meta, expressions}, declared, env) when is_list(expressions) do
    {resolved, declared_after} =
      Enum.map_reduce(expressions, declared, &resolve_names(&1, &2, env))

    {{:__block__, meta, resolved}, declared_after}
  end

  # A clause and a block given to do:, else: and the like are scopes of their own: what they
  # declare is gone once they end.
  defp resolve_names({:->, meta, [args, body]}, declared, env) do
    {resolved_args, _declared} = resolve_names(args, declared, env)
    {resolved_body, _declared} = resolve_names(body, declared, env)

    {{:->, meta, [resolved_args, resolved_body]}, declared}
  end

  defp resolve_names({key, value}, declared, env)
       when key in [:after, :catch, :do, :else, :rescue] do
    {resolved, _declared} = resolve_names(value, declared, env)

    {{key, resolved}, declared}
  end

  defp resolve_names({head, meta, args}, declared, env) when is_list(args) do
    {resolved_head, declared_after_head} = resolve_names(head, declared, env)

    {resolved_args, declared_after} =
      Enum.map_reduce(args, declared_after_head, &resolve_names(&1, &2, env))

    {{resolved_head, meta, resolved_args}, declared_after}
  end

  defp resolve_names({left, right}, declared, env) do
    {resolved_left, declared_after_left} = resolve_names(left, declared, env)
    {resolved_right, declared_after} = resolve_names(right, declared_after_left, env)

    {{resolved_left, resolved_right}, declared_after}
  end

  defp resolve_names(list, declared, env) when is_list(list),
    do: Enum.map_reduce(list, declared, &resolve_names(&1, &2, env))

  defp resolve_names(ast, declared, _env), do: {ast, declared}

  defp state_name?(module, name) do
    List.keymember?(module.__state__(), name, 0)
  end

  defp unset_hint(module, name) do
    cond do
      state_name?(module, name) ->
        "give it a default or set it in init/3"

      Reflection.page?(module) ->
        "pass it as a param of the page"

      module.__props__()
      |> List.keyfind(name, 0)
      |> elem(2)
      |> Keyword.has_key?(:from_context) ->
        "the context has no such key"

      true ->
        "give it a default or pass it"
    end
  end

  # The body names only what its head binds of the module's fields, whether it reads one or binds a
  # local under one's name. Inside a query macro's arguments after the source a bare name is the
  # queried row's, so only what is pinned there is read.
  defp validate_body!({{name, _args, arg_names, body, line}, _type}, fields, env) do
    state = %{
      arg_names: arg_names,
      body_aliases: [],
      env: env,
      fields: fields,
      line: line,
      name: name,
      pattern?: false,
      query_aliases: [],
      query_imports: []
    }

    walk_body(body, state)

    :ok
  end

  defp validate_field_name!(var_name, %{name: var_name, pattern?: false} = state) do
    compile_error!(
      "derived field #{inspect(var_name)} in #{module_label(state.env)} reads itself - a derived field is computed from other fields",
      state.env,
      state.line
    )
  end

  defp validate_field_name!(var_name, %{name: var_name, pattern?: true} = state) do
    compile_error!(
      "#{var_name} is the name of derived field #{inspect(var_name)} in #{module_label(state.env)}, so its function can't bind a local of that name - give the local another name",
      state.env,
      state.line
    )
  end

  defp validate_field_name!(var_name, state) do
    with {:ok, holder} <- Map.fetch(state.fields, var_name),
         false <- var_name in state.arg_names do
      message =
        if state.pattern? do
          "#{var_name} is a #{holder} of #{module_label(state.env)}, so derived field #{inspect(state.name)}'s function can't bind a local of that name - give the local another name"
        else
          "#{var_name} is a #{holder} of #{module_label(state.env)}, which derived field #{inspect(state.name)}'s function doesn't name - add it to the head to read it"
        end

      compile_error!(message, state.env, state.line)
    end

    :ok
  end

  defp validate_head!({{name, _args, arg_names, _body, line}, _type}, fields, env) do
    Hologram.Derived.validate_head!(
      env.module,
      name,
      arg_names,
      Map.keys(fields),
      {env.file, line}
    )
  end

  defp validate_names!(declarations, inputs, env) do
    cid_holder =
      if Module.defines?(env.module, {:__is_hologram_page__, 0}),
        do: "the layout's cid prop",
        else: "the cid prop"

    Enum.reduce(declarations, MapSet.new(), fn {{name, _args, _arg_names, _body, line}, _type},
                                               declared ->
      holder =
        cond do
          name == :cid -> cid_holder
          MapSet.member?(declared, name) -> "another derived field"
          holder = Map.get(inputs, name) -> with_article(holder)
          true -> nil
        end

      if holder do
        compile_error!(
          "derived field #{inspect(name)} in #{module_label(env)} has the same name as #{holder}, which it would shadow - give them different names",
          env,
          line
        )
      end

      MapSet.put(declared, name)
    end)
  end

  defp validate_query_type!(term, entry, module) do
    matches? =
      case {entry.type, term} do
        {[entity], %Query{cardinality: :set, entity: entity}} -> true
        {entity, %Query{cardinality: :one, entity: entity}} -> true
        {:integer, %Query{cardinality: :count}} -> true
        _other -> false
      end

    if not matches? do
      raise Hologram.MisuseError,
        message:
          "derived field #{inspect(entry.name)} in #{Reflection.module_name(module)} is declared #{inspect(entry.type)}, but its query is #{query_description(term)}"
    end

    :ok
  end

  defp validate_value_type!(value, entry, module) do
    if not value_of_type?(value, entry.type) do
      raise Hologram.MisuseError,
        message:
          "derived field #{inspect(entry.name)} in #{Reflection.module_name(module)} is declared #{inspect(entry.type)}, but computed #{inspect(value)}"
    end

    :ok
  end

  # nil stands for no value in every type, a float takes an integer as Elixir's arithmetic does, and
  # a type with no test of its own takes anything.
  defp value_of_type?(nil, _type), do: true

  defp value_of_type?(value, [element_type]) when is_atom(element_type) do
    if Reflection.alias?(element_type) and Reflection.entity?(element_type),
      do: is_list(value) and Enum.all?(value, &is_struct(&1, element_type)),
      else: true
  end

  defp value_of_type?(value, :atom), do: is_atom(value)

  defp value_of_type?(value, :boolean), do: is_boolean(value)

  defp value_of_type?(value, :float), do: is_number(value)

  defp value_of_type?(value, :integer), do: is_integer(value)

  defp value_of_type?(value, :list), do: is_list(value)

  defp value_of_type?(value, :map), do: is_map(value)

  defp value_of_type?(value, :string), do: is_binary(value)

  defp value_of_type?(value, type) when is_atom(type) do
    if Reflection.alias?(type) and Reflection.entity?(type),
      do: is_struct(value, type),
      else: true
  end

  defp value_of_type?(_value, _type), do: true

  # Each walk returns the state the rest of a block is walked with, which is what carries an import
  # or alias of Hologram.Query to the expressions after it.
  defp walk_body({:@, _meta, [_attribute]}, state), do: state

  # A capture names a function, not a variable.
  defp walk_body({:&, _meta, [{:/, _slash_meta, [{name, _name_meta, context}, arity]}]}, state)
       when is_atom(name) and is_atom(context) and is_integer(arity),
       do: state

  defp walk_body({:__block__, _meta, expressions}, state) when is_list(expressions) do
    Enum.reduce(expressions, state, &walk_body/2)
  end

  defp walk_body({:import, _meta, [module_ast | opts]}, state) do
    if query_module?(module_ast, state) do
      imported =
        case opts do
          [[only: only]] when is_list(only) -> Enum.filter(@query_macros, &(&1 in only))
          _all -> @query_macros
        end

      %{state | query_imports: imported ++ state.query_imports}
    else
      state
    end
  end

  # A multi-alias declares a name for each module inside its braces, each joined onto the base.
  defp walk_body(
         {:alias, _meta, [{{:., _dot_meta, [base, :{}]}, _braces_meta, members} | _opts]},
         state
       ) do
    base_module = Macro.expand(base, state.env)

    Enum.reduce(members, state, fn
      {:__aliases__, _member_meta, segments}, acc ->
        name = List.last(segments)

        query_aliases =
          if query_member?(base_module, segments),
            do: [name | acc.query_aliases],
            else: acc.query_aliases -- [name]

        %{acc | body_aliases: [name | acc.body_aliases], query_aliases: query_aliases}

      _member, acc ->
        acc
    end)
  end

  # The names a directive declares stand for its module from then on: Hologram.Query's are read as
  # the query module, and any other's shadows an alias of the module's own of the same name.
  defp walk_body({directive, _meta, [module_ast | opts]}, state)
       when directive in [:alias, :require] do
    names = aliased_names(directive, module_ast, opts)

    query_aliases =
      if query_module?(module_ast, state),
        do: names ++ state.query_aliases,
        else: state.query_aliases -- names

    %{state | body_aliases: names ++ state.body_aliases, query_aliases: query_aliases}
  end

  defp walk_body({:=, _meta, [left, right]}, state) do
    walk_body(right, state)
    walk_pattern(left, state)

    state
  end

  defp walk_body({:->, _meta, [[{:when, _when_meta, patterns_and_guard}], body]}, state) do
    {patterns, [guard]} = Enum.split(patterns_and_guard, -1)

    Enum.each(patterns, &walk_pattern(&1, state))
    walk_body(guard, state)
    walk_body(body, state)

    state
  end

  defp walk_body({:->, _meta, [patterns, body]}, state) when is_list(patterns) do
    Enum.each(patterns, &walk_pattern(&1, state))
    walk_body(body, state)

    state
  end

  defp walk_body({:<-, _meta, [left, right]}, state) do
    walk_body(right, state)
    walk_pattern(left, state)

    state
  end

  defp walk_body({:<<>>, _meta, segments}, state) when is_list(segments) do
    Enum.each(segments, &walk_segment(&1, state))

    state
  end

  defp walk_body({:^, _meta, [expr]}, state) do
    walk_body(expr, %{state | pattern?: false})

    state
  end

  defp walk_body({:|>, _meta, [left, right]}, state) do
    walk_body(left, state)

    if query_macro?(right, 1, state) do
      {_name, _meta, args} = right

      walk_pins(args, state)
    else
      walk_body(right, state)
    end

    state
  end

  defp walk_body({_call, _meta, [source | rest]} = ast, state) when is_list(rest) do
    if query_macro?(ast, 0, state) do
      walk_body(source, state)
      walk_pins(rest, state)
    else
      walk_children(ast, state)
    end

    state
  end

  defp walk_body({var_name, _meta, nil}, state) when is_atom(var_name) do
    validate_field_name!(var_name, state)

    state
  end

  defp walk_body(ast, state) do
    walk_children(ast, state)

    state
  end

  defp walk_children({head, _meta, args}, state) when is_list(args) do
    walk_body(head, state)
    Enum.each(args, &walk_body(&1, state))
  end

  defp walk_children({left, right}, state) do
    walk_body(left, state)
    walk_body(right, state)
  end

  defp walk_children(list, state) when is_list(list), do: Enum.each(list, &walk_body(&1, state))

  defp walk_children(_ast, _state), do: :ok

  defp walk_pattern(ast, state), do: walk_body(ast, %{state | pattern?: true})

  defp walk_pins({:^, _meta, [expr]}, state), do: walk_body(expr, %{state | pattern?: false})

  defp walk_pins({head, _meta, args}, state) when is_list(args) do
    walk_pins(head, state)
    Enum.each(args, &walk_pins(&1, state))
  end

  defp walk_pins({left, right}, state) do
    walk_pins(left, state)
    walk_pins(right, state)
  end

  defp walk_pins(list, state) when is_list(list), do: Enum.each(list, &walk_pins(&1, state))

  defp walk_pins(_ast, _state), do: :ok

  # A segment's type specifiers are no variables - only what size/1 and unit/1 take is read.
  defp walk_segment({:"::", _meta, [value, spec]}, state) do
    walk_body(value, state)
    walk_specifiers(spec, %{state | pattern?: false})
  end

  defp walk_segment(segment, state), do: walk_body(segment, state)

  defp walk_specifiers({:-, _meta, [left, right]}, state) do
    walk_specifiers(left, state)
    walk_specifiers(right, state)
  end

  defp walk_specifiers({:*, _meta, [left, right]}, state) do
    walk_specifiers(left, state)
    walk_specifiers(right, state)
  end

  defp walk_specifiers({specifier, _meta, [arg]}, state) when specifier in [:size, :unit],
    do: walk_body(arg, state)

  defp walk_specifiers(_spec, _state), do: :ok

  defp with_article("state entry"), do: "a state entry"

  defp with_article(holder), do: "a #{holder}"
end
