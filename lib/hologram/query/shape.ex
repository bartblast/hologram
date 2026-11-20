defmodule Hologram.Query.Shape do
  @moduledoc false

  # The shape of a query server code writes on an entity type: the type and the stages called on it,
  # in order, with what each stage was given and every pinned value a placeholder. A query read on
  # the server - DB.read/1 in a page, a command, a mutation or a job - is built at runtime, so the
  # build knows it only by the code that writes it. The stage macros record the shapes they stand
  # in, and the build replays them into the indexes those reads need (see
  # Hologram.Compiler.build_index_needs/5).
  #
  # Recorded into the module the stage is written in, under a persisted attribute, so the shapes
  # travel with its beam: the build reads them with the module's other facts (see
  # Hologram.Reflection.beam_info/1), and a module whose beam changed is read again.
  #
  # Each stage macro records the chain it ends, so a pipe of three stages records three chains, the
  # shorter ones leading the longer - their needs are among the longer ones', which the index
  # selection serves with the same indexes. A chain is recorded only when it starts at an entity
  # type - an alias, __MODULE__ or a module attribute holding one - and goes through stage calls
  # alone, so a query held in a variable and a pinned predicate list record nothing: what they read
  # is known only at runtime. An include holding a pin is left out of the chain rather than ending
  # it, since what it adds is the needs of the sets it includes, not of the rows the chain reads -
  # and a list keeps the entries that hold no pin. A shape is data only - the replay judges it
  # against the entity types.
  #
  # A chain is recorded in every module that writes one, whatever tier its function runs on, so a
  # query only the browser reads can add an index no server statement uses.

  alias Hologram.CompileError
  alias Hologram.Query.Expression
  alias Hologram.Query.Placeholder
  alias Hologram.Query.Stage

  @attribute :__hologram_query_shapes__

  # The stages a chain goes through, each with its arity.
  @stages [
    count: 1,
    filter: 2,
    include: 2,
    one: 1,
    paginate: 2,
    skip: 2,
    sort: 2,
    take: 2,
    trust: 1
  ]

  @type t :: {module, list({atom, list})}

  @doc """
  Returns the name of the persisted attribute the shapes are recorded under.
  """
  @spec attribute() :: atom
  def attribute, do: @attribute

  @doc """
  Records the shape of the given stage call - the stage's name and its arguments as written, the
  query first - into the module the given env is compiling, when the call ends a chain that starts
  at an entity type alias. Records nothing outside an open module, and a shape the module already
  holds once.
  """
  @spec record(atom, list(Macro.t()), Macro.Env.t()) :: :ok
  def record(stage, args, env) do
    module = env.module

    with true <- module != nil and Module.open?(module),
         {:ok, {_entity, [_stage | _rest]} = shape} <- chain(stage, args, env) do
      put(module, shape)
    end

    :ok
  rescue
    # Recording never changes whether a module compiles, or what its compile reports.
    _error -> :ok
  end

  @doc """
  Replays the given shape through the query stages and returns the normalized query term, or
  :error when a stage refuses it - the alias names no entity type, a name is not one the type
  declares, a placeholder stands where the stage takes only a value it knows.
  """
  @spec replay(t) :: {:ok, Hologram.Query.t()} | :error
  def replay({entity, stages}) do
    term =
      Enum.reduce(stages, entity, fn {stage, args}, query ->
        apply(Stage, stage, [query | args])
      end)

    {:ok, Stage.normalize(term)}
  rescue
    _error -> :error
  end

  defp chain(stage, [query | args], env) do
    with {:ok, {entity, stages}} <- head(query, env) do
      case lower(stage, args, env) do
        {:ok, values} -> {:ok, {entity, Enum.concat(stages, [{stage, values}])}}
        :leave_out -> {:ok, {entity, stages}}
        :error -> :error
      end
    end
  end

  defp entity_head(entity) when is_atom(entity) and entity not in [nil, true, false],
    do: {:ok, {entity, []}}

  defp entity_head(_value), do: :error

  defp head({:|>, _meta, [left, right]}, env), do: head(Macro.pipe(left, right, 0), env)

  defp head({:__aliases__, _meta, _segments} = ast, env), do: entity_head(Macro.expand(ast, env))

  defp head({:__MODULE__, _meta, context}, env) when is_atom(context), do: entity_head(env.module)

  defp head({:@, _meta, [{name, _attribute_meta, context}]}, env)
       when is_atom(name) and is_atom(context) do
    entity_head(Module.get_attribute(env.module, name))
  end

  defp head(ast, env) do
    case stage_call(ast, env) do
      {:ok, stage, args} -> chain(stage, args, env)
      :error -> :error
    end
  end

  # What a stage was given, lowered the way its macro lowers it, with each pinned value a placeholder
  # named after the variable it pins. A malformed argument records nothing: the stage's own macro
  # raises on it.
  defp lower(stage, [], _env) when stage in [:count, :one, :trust], do: {:ok, []}

  defp lower(:filter, [{:^, _meta, [_expr]}], _env), do: :error

  # A list keeps its entries the build knows.
  defp lower(:include, [[_entry | _rest] = arg], env) do
    case Enum.reject(arg, &pinned?/1) do
      [] -> :leave_out
      known_entries -> lower_value(:include, known_entries, env)
    end
  end

  defp lower(:include, [arg], env) do
    if pinned?(arg), do: :leave_out, else: lower_value(:include, arg, env)
  end

  # Pinned whole, the options are a page and a size known at runtime, which bound the read alike.
  defp lower(:paginate, [{:^, _meta, [expr]}], _env) do
    placeholder = %Placeholder{name: placeholder_name(expr)}

    {:ok, [[page: placeholder, size: placeholder]]}
  end

  defp lower(stage, [arg], env), do: lower_value(stage, arg, env)

  defp lower_arg(arg, :filter, env), do: Expression.predicates(arg, env)

  defp lower_arg(arg, :include, env), do: Expression.inclusion(arg, env)

  defp lower_arg(arg, :paginate, env), do: Expression.pagination(arg, env)

  defp lower_arg(arg, :skip, env), do: Expression.bound(arg, :skip, env)

  defp lower_arg(arg, :sort, env), do: Expression.ordering(arg, env)

  defp lower_arg(arg, :take, env), do: Expression.bound(arg, :take, env)

  defp lower_value(stage, arg, env) do
    lowered =
      arg
      |> Macro.prewalk(&placeholder/1)
      |> lower_arg(stage, env)

    with {:ok, value} <- value(lowered, env), do: {:ok, [value]}
  rescue
    CompileError -> :error
  end

  defp pinned?(ast) do
    {_ast, pinned?} =
      Macro.prewalk(ast, false, fn
        {:^, _meta, [_expr]} = node, _pinned? -> {node, true}
        node, pinned? -> {node, pinned?}
      end)

    pinned?
  end

  defp placeholder({:^, meta, [expr]}) do
    {:^, meta, [Macro.escape(%Placeholder{name: placeholder_name(expr)})]}
  end

  defp placeholder(ast), do: ast

  defp placeholder_name({name, _meta, context}) when is_atom(name) and is_atom(context), do: name

  defp placeholder_name(_expr), do: :pinned

  # Built as the struct, so that a range the stage refuses - empty, or with a step other than 1 -
  # is recorded for the replay to refuse, rather than warned about or raised on here.
  defp range(bounds, env) do
    case values(bounds, env) do
      {:ok, [first, last, step]}
      when is_integer(first) and is_integer(last) and is_integer(step) ->
        {:ok, %Range{first: first, last: last, step: step}}

      _otherwise ->
        :error
    end
  end

  defp put(module, shape) do
    if !Module.has_attribute?(module, @attribute) do
      Module.register_attribute(module, @attribute, accumulate: true, persist: true)
    end

    if shape not in Module.get_attribute(module, @attribute) do
      Module.put_attribute(module, @attribute, shape)
    end
  end

  # A stage of Hologram.Query, called unqualified where the module imports it or through the
  # module, an alias of it included.
  defp stage_call({{:., _dot_meta, [module_ast, name]}, _meta, args}, env)
       when is_atom(name) and is_list(args) do
    if {name, length(args)} in @stages and Macro.expand(module_ast, env) == Hologram.Query do
      {:ok, name, args}
    else
      :error
    end
  end

  defp stage_call({name, _meta, args}, env) when is_atom(name) and is_list(args) do
    arity = length(args)

    if {name, arity} in @stages and
         match?([{_kind, Hologram.Query} | _rest], Macro.Env.lookup_import(env, {name, arity})) do
      {:ok, name, args}
    else
      :error
    end
  end

  defp stage_call(_ast, _env), do: :error

  # The value a lowered argument evaluates to, which holds literals and placeholders alone once its
  # pins are placeholders - :error for anything else.
  defp value(list, env) when is_list(list), do: values(list, env)

  defp value({:__aliases__, _meta, _segments} = ast, env) do
    case Macro.expand(ast, env) do
      module when is_atom(module) -> {:ok, module}
      _expanded -> :error
    end
  end

  defp value({:{}, _meta, elements}, env) when is_list(elements) do
    with {:ok, values} <- values(elements, env), do: {:ok, List.to_tuple(values)}
  end

  defp value({:%{}, _meta, pairs}, env) when is_list(pairs) do
    with {:ok, values} <- values(pairs, env), do: {:ok, Map.new(values)}
  end

  defp value({sign, _meta, [number]}, _env) when sign in [:+, :-] and is_number(number) do
    {:ok, apply(Kernel, sign, [number])}
  end

  defp value({:.., _meta, [first, last]}, env), do: range([first, last, 1], env)

  defp value({:..//, _meta, [_first, _last, _step] = bounds}, env), do: range(bounds, env)

  # A membership in a range with a pinned bound: the two comparisons the range stands for (see
  # Hologram.Query.Stage), since placeholders make no range. A step of 1 written out is the same
  # range. The comparisons ask for an orderable attribute where a range asks for an integer one, so
  # a pinned range on another orderable type, which raises whenever it runs, still replays into a
  # range need - replay judges what a read needs if it runs, as it does wherever a placeholder
  # stands.
  defp value({:in, {:..//, meta, [first, last, 1]}}, env),
    do: value({:in, {:.., meta, [first, last]}}, env)

  defp value({:in, {:.., _meta, [first, last]}}, env) do
    case values([first, last], env) do
      {:ok, [first, last]} when is_integer(first) and is_integer(last) ->
        {:ok, {:in, %Range{first: first, last: last, step: 1}}}

      {:ok, [first, last]} ->
        if Enum.any?([first, last], &match?(%Placeholder{}, &1)),
          do: {:ok, [{:>=, first}, {:<=, last}]},
          else: :error

      :error ->
        :error
    end
  end

  defp value({left, right}, env) do
    with {:ok, [left, right]} <- values([left, right], env), do: {:ok, {left, right}}
  end

  defp value(literal, _env) when is_atom(literal) or is_number(literal) or is_binary(literal),
    do: {:ok, literal}

  defp value(_ast, _env), do: :error

  defp values([], _env), do: {:ok, []}

  defp values([ast | rest], env) do
    with {:ok, value} <- value(ast, env),
         {:ok, rest_values} <- values(rest, env) do
      {:ok, [value | rest_values]}
    end
  end
end
