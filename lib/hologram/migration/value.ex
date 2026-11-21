defmodule Hologram.Migration.Value do
  @moduledoc false

  # What a `backfill:` computes from each row, as data the migration's op carries. A constant
  # stays the plain value it was written as, so a struct here always means a computed backfill:
  # an attribute's value is never a struct.
  #
  # Lowering runs at expansion and judges the spelling only. What a name reads depends on the
  # model at the op's point in the file's history, which isn't known here. The term reuses the
  # tags of Hologram.Entity.Derived's definitions where they mean the same.

  alias Hologram.Entity.Model
  alias Hologram.Migration.Value.Resolver
  alias Hologram.Query.Expression

  @enforce_keys [:term]
  defstruct [:term]

  @type expression ::
          {:value, any}
          | {:name, list(atom)}
          | {:concat, list(expression)}
          | {:split, expression, expression}
          | {:at, expression, expression}
          | {:coalesce, list(expression)}
          | {:count, set}
          | {:most_common, set, atom}

  @type set :: {:relationship, list(atom)}

  @type t :: %__MODULE__{term: expression}

  @type fill :: %{
          backfill: {:constant, any} | {:computed, %{term: Resolver.resolved(), type: any}},
          entity: module,
          kind: :attribute | :relationship,
          line: pos_integer,
          member: atom,
          nulls_only: boolean
        }

  # The largest position `at` takes: it's rendered into the statement as a literal.
  @max_position 1_000_000

  # Names spelled like a variable that read the surrounding code rather than a field.
  @special_names [:__CALLER__, :__DIR__, :__ENV__, :__MODULE__, :__STACKTRACE__]

  # What each word takes, as its arity refusal says it.
  @word_arguments %{
    at: "a split and a position",
    coalesce: "two or more values",
    count: "a relationship",
    most_common: "a relationship and an attribute",
    split: "a string and a separator"
  }

  @words Map.keys(@word_arguments)

  # The ops a backfill rides, in their options or changes.
  @backfill_ops [:add_attribute, :add_relationship, :change_attribute, :change_relationship]

  # The query stages a query from an entity type is built with.
  @stages [:filter, :include, :one, :paginate, :skip, :sort, :take]

  # Forms holding a value of the surrounding code, however they're spelled.
  @value_forms [:%, :%{}, :&, :@, :__aliases__, :fn, :{}]

  @doc """
  Returns what the given ops fill, in op order: one entry per op carrying a backfill, constant or
  computed, a computed one resolved against the model right before its op. An entry fills only the
  rows holding nil when its op turns a member required.

  This is the one reading of a file's backfills, for the fold, the renderer and anything running
  them on a single row.
  """
  @spec fills(list(%{atom => any}), %{atom => any}) :: list(fill)
  def fills(ops, pre_model) do
    {fills, _post_model} =
      Enum.reduce(ops, {[], pre_model}, fn op, {acc, model} ->
        next_model = Model.fold_op(model, op)

        {prepend_fill(acc, op, model, next_model), next_model}
      end)

    Enum.reverse(fills)
  end

  @doc """
  Lowers the given `backfill:` value of a migration op to the AST the op carries.

  A literal stays as written, and a pinned expression becomes that expression: both are constants.
  Anything else is an expression in the backfill words, lowered to the AST of a `%Value{}`, written
  out as a map so that the migration doesn't use this module at compile time. Each pinned value in
  it stays the caller's code, evaluated where the op's other arguments are.

  Raises Hologram.CompileError, located at the offending node, on a `fn` or a capture, a call that
  is no word, a word given the wrong arguments, and a value of the surrounding code left unpinned.
  """
  @spec lower(Macro.t(), Macro.Env.t()) :: Macro.t()
  def lower({:^, _meta, [expr]}, _env), do: expr

  def lower({:fn, _meta, _clauses} = ast, env), do: refuse_fn(ast, env)

  def lower({:&, _meta, _args} = ast, env), do: refuse_capture(ast, env)

  def lower(ast, env) do
    if constant?(ast) do
      ast
    else
      {:%{}, [], [__struct__: __MODULE__, term: expression(ast, env)]}
    end
  end

  @doc """
  Returns the largest position `at` takes.
  """
  @spec max_position() :: pos_integer
  def max_position, do: @max_position

  @doc """
  Resolves the given backfill against the given model for the given member (see
  `Hologram.Migration.Value.Resolver.resolve!/4`).
  """
  @spec resolve!(t, %{atom => any}, module, Resolver.target()) ::
          %{term: Resolver.resolved(), type: Resolver.type()}
  defdelegate resolve!(value, model, entity_type, target), to: Resolver

  @doc """
  Validates that every computed backfill of the given evaluated ops holds a term lowering can
  produce. Op options may come from a call, so a migration could build the struct by hand, and
  what a term runs must never be anything the call check hasn't seen.

  Raises Hologram.CompileError, located at the op in the given file, on any other term.
  """
  @spec validate_ops!(list(%{atom => any}), String.t()) :: :ok
  def validate_ops!(ops, file) do
    for op <- ops,
        %{__struct__: __MODULE__} = value <- op_backfills(op),
        not valid_term?(Map.get(value, :term)) do
      raise Hologram.CompileError,
        message:
          "a backfill holds a computed value that wasn't written as a backfill expression - " <>
            "write the expression in the op",
        file: file,
        line: op.line
    end

    :ok
  end

  defp attribute({name, _meta, context}, _word, _env)
       when is_atom(name) and is_atom(context) and name not in @special_names do
    name
  end

  defp attribute(atom, word, env) when is_atom(atom) and atom not in [nil, true, false] do
    Expression.compile_error!(
      "#{word} names the attribute with a bare name, got: #{inspect(atom)} - write #{atom}",
      atom,
      env
    )
  end

  defp attribute(ast, word, env) do
    Expression.compile_error!(
      "#{word} names the attribute with a bare name, got: #{Macro.to_string(ast)}",
      ast,
      env
    )
  end

  defp constant?({sign, _meta, [number]}) when sign in [:+, :-], do: is_number(number)

  # An alias headed by anything but a name reads the surrounding code, like @mod.Tier.
  defp constant?({:__aliases__, _meta, [head | _rest]}), do: is_atom(head)

  defp constant?(ast), do: is_atom(ast) or is_number(ast) or is_binary(ast)

  defp expression({:|>, _meta, _args} = ast, env) do
    ast
    |> unpipe(env)
    |> expression(env)
  end

  defp expression({:^, _meta, [expr]}, _env), do: {:value, expr}

  defp expression({:fn, _meta, _clauses} = ast, env), do: refuse_fn(ast, env)

  defp expression({:&, _meta, _args} = ast, env), do: refuse_capture(ast, env)

  defp expression({:<>, _meta, [_left, _right]} = ast, env) do
    {:concat, operands(ast, env)}
  end

  defp expression({:at, _meta, [list, position]}, env) do
    {:{}, [], [:at, split(list, env), position(position, env)]}
  end

  defp expression({:split, _meta, [_text, _separator]} = ast, env) do
    Expression.compile_error!(
      "a backfill can't store a list, got: #{Macro.to_string(ast)} - pick one part with at, " <>
        "like #{Macro.to_string(ast)} |> at(0)",
      ast,
      env
    )
  end

  defp expression({:coalesce, _meta, [_first, _second | _rest] = values}, env) do
    {:coalesce, Enum.map(values, &expression(&1, env))}
  end

  defp expression({:count, _meta, [set]}, env), do: {:count, set(set, :count, env)}

  defp expression({:most_common, _meta, [set, attribute]}, env) do
    {:{}, [],
     [
       :most_common,
       set(set, :most_common, env),
       attribute(attribute, :most_common, env)
     ]}
  end

  defp expression({stage, _meta, args} = ast, env) when stage in @stages and is_list(args) do
    refuse_type_source(ast, env)
  end

  defp expression(nil, env) do
    Expression.compile_error!(
      "a backfill expression can't hold nil - nil is the absence a backfill exists to fill",
      nil,
      env
    )
  end

  defp expression(ast, env) do
    names = path(ast)

    cond do
      constant?(ast) -> {:value, ast}
      names != nil -> {:name, names}
      true -> refuse(ast, env)
    end
  end

  defp fill_member(%{entity: entity, name: name, op: op}, _model, next_model) do
    {kind, list_key} =
      if op in [:add_attribute, :change_attribute],
        do: {:attribute, :attributes},
        else: {:relationship, :relationships}

    {kind, List.keyfind(next_model.entities[entity][list_key], name, 0)}
  end

  defp interpolated?(parts) do
    Enum.any?(parts, fn
      {:"::", _meta, [{{:., _dot_meta, [Kernel, :to_string]}, _call_meta, _args}, _type]} -> true
      _part -> false
    end)
  end

  defp op_backfills(%{op: kind} = op) when kind in @backfill_ops do
    op
    |> Map.take([:changes, :opts])
    |> Map.values()
    |> Enum.flat_map(&option_backfills/1)
  end

  defp op_backfills(_op), do: []

  defp operands({:<>, _meta, [left, right]}, env) do
    operands(left, env) ++ operands(right, env)
  end

  defp operands(ast, env), do: [expression(ast, env)]

  # Every value under :backfill in the given options, however they were built: the model takes
  # some ops' options unchecked, so they may be a map or repeat the key.
  defp option_backfills(%{backfill: value}), do: [value]

  defp option_backfills(options) when is_list(options) do
    if List.improper?(options) do
      []
    else
      for {:backfill, value} <- options, do: value
    end
  end

  defp option_backfills(_options), do: []

  # The names of a bare name or a dot chain on one, nil for anything else. A call with
  # parentheses is no path.
  defp path(ast), do: path(ast, [])

  defp path({name, _meta, context}, names)
       when is_atom(name) and is_atom(context) and name not in @special_names do
    [name | names]
  end

  defp path({{:., _dot_meta, [left, name]}, meta, []}, names) when is_atom(name) do
    if meta[:no_parens], do: path(left, [name | names])
  end

  defp path(_ast, _names), do: nil

  # What a pipe can go into: a word or a remote call, which then refuses on its own terms.
  defp pipeable?(form, _args) when not is_atom(form), do: true

  defp pipeable?(form, args) do
    form not in [:^, :|>, :<<>>, :__block__ | @value_forms] and not sigil?(form) and
      not Macro.operator?(form, length(args))
  end

  defp position({:^, _meta, [expr]}, _env), do: {:value, expr}

  defp position(n, _env) when is_integer(n) and n in 0..@max_position, do: {:value, n}

  defp position({:+, _meta, [n]}, _env) when is_integer(n) and n in 0..@max_position do
    {:value, n}
  end

  defp position({:-, _meta, [0]}, _env), do: {:value, 0}

  defp position({:-, _meta, [n]} = ast, env) when is_integer(n) do
    Expression.compile_error!(
      "at counts from 0, got: #{Macro.to_string(ast)} - it can't count from the end yet",
      ast,
      env
    )
  end

  defp position(ast, env) do
    Expression.compile_error!(
      "at takes a position from 0 to #{@max_position} or a pinned expression, " <>
        "got: #{Macro.to_string(ast)}",
      ast,
      env
    )
  end

  defp prepend_fill(acc, op, model, next_model) do
    case op_backfills(op) do
      [] ->
        acc

      [backfill | _rest] ->
        {kind, member} = fill_member(op, model, next_model)

        [
          %{
            backfill: resolved_backfill(backfill, op, kind, member, model),
            entity: op.entity,
            kind: kind,
            line: op.line,
            member: op.name,
            nulls_only: op.op in [:change_attribute, :change_relationship]
          }
          | acc
        ]
    end
  end

  @spec refuse(Macro.t(), Macro.Env.t()) :: no_return
  defp refuse({word, _meta, args} = ast, env) when word in @words and is_list(args) do
    Expression.compile_error!(
      "#{word} takes #{Map.fetch!(@word_arguments, word)}, got: #{Macro.to_string(ast)}",
      ast,
      env
    )
  end

  defp refuse({:<<>>, _meta, parts} = ast, env) do
    if interpolated?(parts) do
      Expression.compile_error!(
        "a backfill joins strings with <>, got: #{Macro.to_string(ast)} - " <>
          ~s(write it like "Trip to " <> destination),
        ast,
        env
      )
    else
      refuse_unpinned(ast, env)
    end
  end

  defp refuse({name, _meta, args} = ast, env)
       when is_atom(name) and is_list(args) and name not in @value_forms do
    if sigil?(name) do
      refuse_unpinned(ast, env)
    else
      Expression.compile_error!(
        "#{name}/#{length(args)} is no backfill word - the words are <>, split, at, coalesce, " <>
          "count and most_common, and a value from the surrounding code is pinned with ^",
        ast,
        env
      )
    end
  end

  defp refuse(ast, env), do: refuse_unpinned(ast, env)

  @spec refuse_capture(Macro.t(), Macro.Env.t()) :: no_return
  defp refuse_capture(ast, env) do
    Expression.compile_error!(
      "a backfill takes no capture, got: #{Macro.to_string(ast)} - a capture hides the fields " <>
        "it reads, so write a fn naming them",
      ast,
      env
    )
  end

  @spec refuse_fn(Macro.t(), Macro.Env.t()) :: no_return
  defp refuse_fn(ast, env) do
    Expression.compile_error!(
      "a backfill can't take a fn yet - write the expression without it",
      ast,
      env
    )
  end

  @spec refuse_pipe(Macro.t(), Macro.t(), Macro.Env.t()) :: no_return
  defp refuse_pipe(right, ast, env) do
    Expression.compile_error!(
      "a backfill pipes into a word called with parentheses, got: #{Macro.to_string(right)}",
      ast,
      env
    )
  end

  @spec refuse_set(Macro.t(), atom, Macro.Env.t()) :: no_return
  defp refuse_set(atom, word, env) when is_atom(atom) and atom not in [nil, true, false] do
    Expression.compile_error!(
      "#{word} names the relationship with a bare name, got: #{inspect(atom)} - write #{atom}",
      atom,
      env
    )
  end

  defp refuse_set(ast, word, env) do
    Expression.compile_error!(
      "#{word} takes a relationship of the row, got: #{Macro.to_string(ast)}",
      ast,
      env
    )
  end

  @spec refuse_type_source(Macro.t(), Macro.Env.t()) :: no_return
  defp refuse_type_source(ast, env) do
    Expression.compile_error!(
      "a backfill without a fn reads the row's own relationships, got: " <>
        "#{Macro.to_string(ast)} - for the rows pointing at this one, write a fn naming its " <>
        "id, like fn id -> Stop |> filter(trip_id == ^id) |> count() end",
      ast,
      env
    )
  end

  @spec refuse_unpinned(Macro.t(), Macro.Env.t()) :: no_return
  defp refuse_unpinned(ast, env) do
    spelled = Macro.to_string(ast)

    Expression.compile_error!(
      "a backfill expression can't read #{spelled} - a value from the surrounding code is " <>
        "pinned: ^#{spelled}",
      ast,
      env
    )
  end

  defp resolved_backfill(%__MODULE__{} = value, op, kind, member, model) do
    {:computed, resolve!(value, model, op.entity, target(kind, member, op))}
  end

  defp resolved_backfill(value, _op, _kind, _member, _model), do: {:constant, value}

  defp separator({:^, _meta, [expr]}, _env), do: {:value, expr}

  defp separator("", env) do
    Expression.compile_error!("split takes a non-empty separator, got: \"\"", "", env)
  end

  defp separator(separator, _env) when is_binary(separator), do: {:value, separator}

  defp separator(ast, env) do
    Expression.compile_error!(
      "split takes a string separator or a pinned expression, got: #{Macro.to_string(ast)}",
      ast,
      env
    )
  end

  defp set(ast, word, env) do
    unpiped = unpipe(ast, env)

    cond do
      type_source?(unpiped, env) -> refuse_type_source(unpiped, env)
      names = path(unpiped) -> {:relationship, names}
      true -> refuse_set(unpiped, word, env)
    end
  end

  defp sigil?(name) do
    name
    |> Atom.to_string()
    |> String.starts_with?("sigil_")
  end

  defp split(ast, env) do
    case unpipe(ast, env) do
      {:split, _meta, [text, separator]} ->
        {:{}, [], [:split, expression(text, env), separator(separator, env)]}

      other ->
        Expression.compile_error!(
          "at reads a part of a split, got: #{Macro.to_string(other)}",
          other,
          env
        )
    end
  end

  defp target(:attribute, {name, type, opts}, op) do
    %{kind: :attribute, line: op.line, name: name, opts: opts, type: type}
  end

  defp target(:relationship, {name, [_target], _opts}, op) do
    raise Hologram.CompileError,
      message:
        "the backfill of #{inspect(name)} on #{inspect(op.entity)} (line #{op.line}) fills a " <>
          "to-many relationship - a backfill fills a value or a to-one reference"
  end

  defp target(:relationship, {name, type, _opts}, op) do
    %{kind: :relationship, line: op.line, name: name, type: type}
  end

  # Whether the given set is a query rather than a relationship of the row: an entity type, or
  # query stages, whatever they start from.
  defp type_source?({:__aliases__, _meta, _segments}, _env), do: true

  defp type_source?({stage, _meta, [source | _rest]}, env) when stage in @stages do
    stage == :filter or
      source
      |> unpipe(env)
      |> type_source?(env)
  end

  defp type_source?(_ast, _env), do: false

  defp unpipe({:|>, _meta, [left, {form, call_meta, args} = right]} = ast, env)
       when is_list(args) do
    if pipeable?(form, args) do
      {form, call_meta, [left | args]}
    else
      refuse_pipe(right, ast, env)
    end
  end

  defp unpipe({:|>, _meta, [_left, right]} = ast, env), do: refuse_pipe(right, ast, env)

  defp unpipe(ast, _env), do: ast

  defp valid_list?(list, min_length) do
    is_list(list) and not List.improper?(list) and length(list) >= min_length
  end

  defp valid_name?(names), do: valid_list?(names, 1) and Enum.all?(names, &is_atom/1)

  defp valid_operand?({:concat, _operands}), do: false

  defp valid_operand?(operand), do: valid_term?(operand)

  defp valid_set?({:relationship, names}), do: valid_name?(names)

  defp valid_set?(_set), do: false

  # The shapes lowering writes: a split only under at, with its separator and position values,
  # and a join flattened.
  defp valid_term?({:value, _value}), do: true

  defp valid_term?({:name, names}), do: valid_name?(names)

  defp valid_term?({:concat, operands}) do
    valid_list?(operands, 2) and Enum.all?(operands, &valid_operand?/1)
  end

  defp valid_term?({:at, {:split, text, {:value, _separator}}, {:value, _position}}) do
    valid_term?(text)
  end

  defp valid_term?({:coalesce, values}) do
    valid_list?(values, 2) and Enum.all?(values, &valid_term?/1)
  end

  defp valid_term?({:count, set}), do: valid_set?(set)

  defp valid_term?({:most_common, set, attribute}) when is_atom(attribute) do
    valid_set?(set)
  end

  defp valid_term?(_term), do: false
end
