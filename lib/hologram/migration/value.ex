defmodule Hologram.Migration.Value do
  @moduledoc false

  # What a `backfill:` computes from each row, as data the migration's op carries. A constant
  # stays the plain value it was written as, so a struct here always means a computed backfill:
  # an attribute's value is never a struct.
  #
  # Lowering runs at expansion and judges the spelling only. What a name reads depends on the
  # model at the op's point in the file's history, which isn't known here. The term reuses the
  # tags of Hologram.Entity.Derived's definitions where they mean the same.

  alias Hologram.DB.Codec
  alias Hologram.Entity.Model
  alias Hologram.Migration.FieldAccess.Definitions
  alias Hologram.Migration.Value.Check
  alias Hologram.Migration.Value.Resolver
  alias Hologram.Query.Expression

  # The largest integer a float holds exactly, as Resolver widens a literal.
  @max_exact_float_integer 9_007_199_254_740_992

  @enforce_keys [:term]
  defstruct [:term, args: []]

  @type expression ::
          {:value, any}
          | {:name, list(atom)}
          | {:concat, list(expression)}
          | {:split, expression, expression}
          | {:at, expression, expression}
          | {:coalesce, list(expression)}
          | {:count, set}
          | {:most_common, set, atom}
          | {:function, module, atom, list(atom)}

  @type set :: {:relationship, list(atom)} | {:referencing, module, atom}

  @type t :: %__MODULE__{args: list(atom), term: expression}

  # How a fn body reads, before the module's own functions are known.
  @type fn_reading :: %{
          arg_asts: list(Macro.t()),
          args: list(atom),
          body: Macro.t(),
          calls: list({atom, non_neg_integer}),
          env: Macro.Env.t(),
          imported: list({atom, non_neg_integer}),
          kind: :elixir | :marked | :query | {:word, {atom, non_neg_integer}},
          query: {:ok, Macro.t()} | {:error, Exception.t()} | :none,
          run_calls: list({atom, non_neg_integer})
        }

  # What map_reduce_quote/5 calls on each part of a quote that runs.
  @type quote_mapper :: (Macro.t(), any, true | :unknown, splicing -> {Macro.t(), any})

  # Whether the function the code is written in splices in an unquote there itself, as def does
  # with an unquote outside any quote: true, false, or :unknown when that's up to the function's
  # other unquotes.
  @type splicing :: boolean | :unknown

  @typep scope :: %{args: list(atom), env: Macro.Env.t(), in_fn: boolean}

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

  # The calls that open a query at the outermost part of a fn body.
  @query_calls @words ++ @stages

  # What can change the meaning of a name inside an Elixir body.
  @scope_changing_forms [:alias, :import, :require]

  # The ones an Elixir body can't call, since nothing else would give them a meaning there.
  @elixir_refused_words [:filter | @words]

  # Forms holding a value of the surrounding code, however they're spelled.
  @value_forms [:%, :%{}, :&, :@, :__aliases__, :fn, :{}]

  @doc """
  Returns the backfill the given op carries, in its options or changes, or :error when it carries
  none.
  """
  @spec fetch_backfill(%{atom => any}) :: {:ok, any} | :error
  def fetch_backfill(op) do
    case op_backfills(op) do
      [backfill | _rest] -> {:ok, backfill}
      [] -> :error
    end
  end

  @doc """
  Returns the kind of the member the given op fills, and the member as the given model, the one
  after the op, holds it.
  """
  @spec fill_member(%{atom => any}, %{atom => any}) :: {:attribute | :relationship, tuple}
  def fill_member(%{entity: entity, name: name, op: op}, next_model) do
    {kind, list_key} =
      if op in [:add_attribute, :change_attribute],
        do: {:attribute, :attributes},
        else: {:relationship, :relationships}

    {kind, List.keyfind(next_model.entities[entity][list_key], name, 0)}
  end

  @doc """
  Returns the target `resolve!/4` takes for the given member of the given kind.

  Raises Hologram.CompileError on a to-many, which holds no value of the row to fill.
  """
  @spec fill_target(:attribute | :relationship, tuple, %{atom => any}) :: Resolver.target()
  def fill_target(:attribute, {name, type, opts}, op) do
    %{kind: :attribute, line: op.line, name: name, opts: opts, type: type}
  end

  def fill_target(:relationship, {name, [_target], _opts}, op) do
    raise Hologram.CompileError,
      message:
        "the backfill of #{inspect(name)} on #{inspect(op.entity)} (line #{op.line}) fills a " <>
          "to-many relationship - a backfill fills a value or a to-one reference"
  end

  def fill_target(:relationship, {name, type, _opts}, op) do
    %{kind: :relationship, line: op.line, name: name, type: type}
  end

  @doc """
  Returns the given constant backfill of the given type as it's stored: a uuid in lowercase, the
  only spelling the database codec and the browser compare, whichever case the file wrote it in,
  a datetime in UTC or a time at microsecond precision, as the database gives them back, and an
  integer a float holds exactly as that float, as a literal in a computed backfill is. A value that
  isn't of the type stays as it is, for the check to refuse.
  """
  @spec normalize_constant(any, atom) :: any
  def normalize_constant(value, :float)
      when is_integer(value) and abs(value) <= @max_exact_float_integer,
      do: value * 1.0

  def normalize_constant(value, :uuid) when is_binary(value), do: String.downcase(value)

  def normalize_constant(value, type) when type in [:datetime, :time] do
    stored = Check.stored_form(value)

    if Resolver.storable?(stored) and Resolver.fits_type?(stored, type) do
      Codec.encode(stored, type)
    else
      value
    end
  end

  def normalize_constant(value, _type), do: value

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
  Returns each local call in the given code with its full arity, a piped call counting the value
  piped in and a capture counting as a call.
  """
  @spec local_calls(Macro.t(), Macro.Env.t()) :: list({atom, non_neg_integer})
  def local_calls(body, env) do
    # The operator is a call too, which an import can change.
    {unpiped, pipes} =
      Macro.prewalk(body, [], fn
        {:|>, _meta, [_left, _right]} = pipe, found ->
          {unpiped_call(pipe, env), [{:|>, 2} | found]}

        node, found ->
          {unpiped_call(node, env), found}
      end)

    {_ast, calls} =
      Macro.prewalk(unpiped, pipes, fn
        {:&, _meta, [{:/, _slash_meta, [{name, _name_meta, context}, arity]}]} = node, found
        when is_atom(name) and is_atom(context) and is_integer(arity) ->
          {node, [{name, arity} | found]}

        {name, _meta, args} = node, found when is_atom(name) and is_list(args) ->
          {node, [{name, length(args)} | found]}

        node, found ->
          {node, found}
      end)

    Enum.uniq(calls)
  end

  @doc """
  Returns each local call the given code may run, as local_calls/2 does, leaving out the calls in
  a quote's own code, which is data. A call only the compiler can tell runs, like in an unquote
  under quote options an attribute holds, is kept.
  """
  @spec may_run_calls(Macro.t(), Macro.Env.t()) :: list({atom, non_neg_integer})
  def may_run_calls(code, env) do
    code
    |> run_code(env, :may_run)
    |> local_calls(env)
  end

  @doc """
  Returns the first of the given local calls that runs a macro the given module defines, other
  than a guard, or nil with none. Such a macro expands where it's called, and code placed at the
  end of the module, as an op's is, would read the attributes there. Takes a module still being
  compiled.
  """
  @spec own_macro(list({atom, non_neg_integer}), module) :: {atom, non_neg_integer} | nil
  def own_macro(calls, module) do
    Enum.find(calls, fn call ->
      (Module.defines?(module, call, :defmacro) or Module.defines?(module, call, :defmacrop)) and
        not Definitions.guard?(module, call)
    end)
  end

  @doc """
  Maps the code a quote runs where it's written, when the given node is one: its options, and
  what its body unquotes. The given splicing says whether the function the node is written in
  splices in an unquote there itself, as def does with one outside any quote: true, false, or
  :unknown when that's up to the function's other unquotes. That function splices before pipes
  expand, so it splices the unquotes of a body piped into a quote whatever the quote's options
  say. An unquote the function splices in is mapped whole, as code with that splicing.

  The given function takes each part, the accumulator, true or :unknown when only the compiler
  can tell whether the part runs, like under options an attribute holds, and the splicing inside
  the part.

  Returns :error for a node that isn't a quote, or a pipe that doesn't expand to one.
  """
  @spec map_reduce_quote(Macro.t(), Macro.Env.t(), splicing, any, quote_mapper) ::
          {:ok, Macro.t(), any} | :error
  def map_reduce_quote({:quote, meta, args}, _env, splicing, acc, fun) when is_list(args) do
    unquotes = quote_unquotes(args)
    options_splicing = options_splicing(args, splicing)
    {args, acc} = map_reduce_quote_args(args, unquotes, options_splicing, acc, fun)

    {:ok, {:quote, meta, args}, acc}
  end

  def map_reduce_quote(
        {pipe, meta, [left, {:quote, quote_meta, args}]} = node,
        env,
        splicing,
        acc,
        fun
      ) do
    case {unpiped_call(node, env), args} do
      # Left of the pipe is the body, which isn't in a quote, so splicing in it is as beside the
      # pipe.
      {{:quote, _meta, [^left]}, _written} ->
        unquotes = quote_unquotes([left])
        {[left], all_acc} = map_reduce_quote_args([left], unquotes, splicing, acc, fun)

        {:ok, {pipe, meta, [left, {:quote, quote_meta, args}]}, all_acc}

      # Left of the pipe are the quote's separate options, which aren't in a quote either.
      {{:quote, _meta, [^left, block]}, [block]} ->
        {options, options_acc} = fun.(left, acc, true, splicing)
        unquotes = quote_unquotes([left, block])
        {block, all_acc} = map_reduce_quote_block(block, unquotes, options_acc, fun)

        {:ok, {pipe, meta, [options, {:quote, quote_meta, [block]}]}, all_acc}

      _call ->
        :error
    end
  end

  def map_reduce_quote(_node, _env, _splicing, _acc, _fun), do: :error

  @doc """
  Lowers the given `backfill:` value of a migration op to the AST the op carries.

  A literal stays as written, and a pinned expression becomes that expression: both are constants.
  Anything else is an expression in the backfill words, lowered to the AST of a `%Value{}`, written
  out as a map so that the migration doesn't use this module at compile time. Each pinned value in
  it stays the caller's code, evaluated where the op's other arguments are. A `fn` is read by
  `read_fn/2` instead.

  Raises Hologram.CompileError, located at the offending node, on a capture, a call that is no
  word, a word given the wrong arguments, and a value of the surrounding code left unpinned.
  """
  @spec lower(Macro.t(), Macro.Env.t()) :: Macro.t()
  def lower({:^, _meta, [expr]}, _env), do: expr

  def lower({:&, _meta, _args} = ast, env), do: refuse_capture(ast, bare_scope(env))

  def lower(ast, env) do
    if constant?(ast) do
      ast
    else
      value_ast(expression(ast, bare_scope(env)), [])
    end
  end

  @doc """
  Reads the given `fn` of a `backfill:`. Whether its body is a query or Elixir can depend on a
  function the module defines below the op, so a refusal of the query reading is kept for
  `choose_fn!/2`, which runs once the module's functions are known.

  Raises Hologram.CompileError on arguments that aren't distinct bare names, on several clauses,
  and on a body that's only a constant.
  """
  @spec read_fn(Macro.t(), Macro.Env.t()) :: fn_reading
  def read_fn({:fn, _meta, clauses} = ast, env) do
    scope = %{args: [], env: env, in_fn: true}
    {arg_asts, args, body} = fn_parts(clauses, ast, scope)
    fn_scope = %{scope | args: args}
    kind = fn_kind(body, fn_scope)
    calls = local_calls(body, env)

    %{
      arg_asts: arg_asts,
      args: args,
      body: body,
      calls: calls,
      env: env,
      imported: Enum.filter(calls, &(elixir_imports(env, &1) != [])),
      kind: kind,
      query: read_query(body, kind, fn_scope),
      # A call in quoted code is data, so only these count as a query(...) or a query word. The
      # calls above keep the quoted ones for the import check, since a quote records the imports
      # in force.
      run_calls: local_calls(run_code(body, env), env)
    }
  end

  @doc """
  Returns the AST of the `%Value{}` of an Elixir `fn` running as the given function of the given
  module.
  """
  @spec function_value(fn_reading, module, atom) :: Macro.t()
  def function_value(%{args: args}, module, function) do
    value_ast({:{}, [], [:function, module, function, args]}, args)
  end

  @doc """
  Returns the AST of the `%Value{}` the query reading of the given `fn` holds, or nil with none.
  """
  @spec fn_value(fn_reading) :: Macro.t() | nil
  def fn_value(%{args: args, query: {:ok, term}}), do: value_ast(term, args)

  def fn_value(_reading), do: nil

  @doc """
  Settles whether the given `fn` of the given module runs as a query or as Elixir.

  A body is a query when it's marked with `query(...)`, is only a field or a path, or its outermost
  part is a word that the module neither imports nor defines. Anything else is Elixir, and reads
  the row's own fields as its arguments.

  Takes the module's environment at its end, where an import written below the op is in force.

  Raises Hologram.CompileError on a query reading that was refused, on a module defining `query/1`
  beside a marked body, on a call an import below the op changes, and on an Elixir body that reads
  nothing of the row, calls a query word or pins a value.
  """
  @spec choose_fn!(fn_reading, Macro.Env.t()) :: :elixir | :query
  def choose_fn!(reading, %{module: module} = env) do
    if {:query, 1} in reading.run_calls and Module.defines?(module, {:query, 1}) do
      Expression.compile_error!(
        "query(...) marks a backfill body as a query, so this module can't define query/1 " <>
          "beside it - rename the function",
        reading.body,
        reading.env
      )
    end

    choose_kind!(reading.kind, reading, env)
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
  what a term runs must never be anything the call check hasn't seen, so a function it runs has to
  be one of the backfill functions the given migration module generated, each given as its module,
  name and arguments.

  Raises Hologram.CompileError, located at the op in the given file, on any other term.
  """
  @spec validate_ops!(
          list(%{atom => any}),
          String.t(),
          module | nil,
          list({module, atom, list(atom)})
        ) :: :ok
  def validate_ops!(ops, file, module \\ nil, backfill_functions \\ []) do
    for op <- ops,
        %{__struct__: __MODULE__} = value <- op_backfills(op),
        not (valid_top_term?(Map.get(value, :term), module, backfill_functions) and
               valid_args?(Map.get(value, :args, [])) and
               function_args_match?(Map.get(value, :term), Map.get(value, :args, []))) do
      raise Hologram.CompileError,
        message:
          "a backfill holds a computed value that wasn't written as a backfill expression - " <>
            "write the expression in the op",
        file: file,
        line: op.line
    end

    :ok
  end

  defp attribute({name, _meta, context}, _word, _scope)
       when is_atom(name) and is_atom(context) and name not in @special_names do
    name
  end

  defp attribute(atom, word, scope) when is_atom(atom) and atom not in [nil, true, false] do
    compile_error!(
      "#{word} names the attribute with a bare name, got: #{inspect(atom)} - write #{atom}",
      atom,
      scope
    )
  end

  defp attribute(ast, word, scope) do
    compile_error!(
      "#{word} names the attribute with a bare name, got: #{Macro.to_string(ast)}",
      ast,
      scope
    )
  end

  defp bare_scope(env), do: %{args: [], env: env, in_fn: false}

  defp call_shape({:|>, _meta, [_left, {name, _call_meta, args}]})
       when is_atom(name) and is_list(args) do
    {name, length(args) + 1}
  end

  defp call_shape({name, _meta, args}) when is_atom(name) and is_list(args) do
    {name, length(args)}
  end

  defp call_shape(_ast), do: nil

  defp call_taken?(call, reading, module) do
    call in reading.imported or Module.defines?(module, call)
  end

  defp choose_kind!(:marked, reading, _env), do: settle_query!(reading)

  defp choose_kind!(:query, reading, _env), do: settle_query!(reading)

  defp choose_kind!({:word, word}, reading, %{module: module} = env) do
    validate_imports_agree!(reading, env)

    if call_taken?(word, reading, module) do
      settle_elixir!(reading, module)
    else
      settle_query!(reading)
    end
  end

  defp choose_kind!(:elixir, reading, %{module: module} = env) do
    validate_imports_agree!(reading, env)

    settle_elixir!(reading, module)
  end

  @spec compile_error!(String.t(), Macro.t(), scope) :: no_return
  defp compile_error!(message, node, %{env: env}) do
    Expression.compile_error!(message, node, env)
  end

  defp constant?({sign, _meta, [number]}) when sign in [:+, :-], do: is_number(number)

  # An alias headed by anything but a name reads the surrounding code, like @mod.Tier.
  defp constant?({:__aliases__, _meta, [head | _rest]}), do: is_atom(head)

  defp constant?(ast), do: is_atom(ast) or is_number(ast) or is_binary(ast)

  # A word imported from Hologram.Query is still the word, and the call check refuses the import.
  defp elixir_imports(env, {name, _arity} = call) do
    imports = Macro.Env.lookup_import(env, call)

    if name in @query_calls do
      Enum.reject(imports, fn {_kind, module} -> module == Hologram.Query end)
    else
      imports
    end
  end

  defp expanded_pipe({:|>, meta, [left, {:|>, _right_meta, [middle, last]}]}, env) do
    expanded_pipe({:|>, meta, [expanded_pipe({:|>, meta, [left, middle]}, env), last]}, env)
  end

  defp expanded_pipe(
         {:|>, meta, [left, {{:., _dot_meta, [receiver, :|>]}, call_meta, [right]} = target]},
         env
       ) do
    if Macro.expand(receiver, env) == Kernel do
      expanded_pipe({:|>, meta, [left, right]}, env)
    else
      {elem(target, 0), call_meta, [left, right]}
    end
  end

  defp expanded_pipe({:|>, _meta, [left, {name, call_meta, context}]}, _env)
       when is_atom(name) and is_atom(context) do
    {name, call_meta, [left]}
  end

  defp expanded_pipe({:|>, _meta, [left, {form, call_meta, args}]}, _env) when is_list(args) do
    {form, call_meta, [left | args]}
  end

  defp expanded_pipe(pipe, _env), do: pipe

  defp expression({:|>, _meta, _args} = ast, scope) do
    ast
    |> unpipe(scope)
    |> expression(scope)
  end

  defp expression({:^, _meta, [expr]}, _scope), do: {:value, expr}

  defp expression({:fn, _meta, _clauses} = ast, scope), do: refuse_fn(ast, scope)

  defp expression({:&, _meta, _args} = ast, scope), do: refuse_capture(ast, scope)

  defp expression({:<>, _meta, [_left, _right]} = ast, scope) do
    {:concat, operands(ast, scope)}
  end

  defp expression({:at, _meta, [list, position]}, scope) do
    {:{}, [], [:at, split(list, scope), position(position, scope)]}
  end

  defp expression({:split, _meta, [_text, _separator]} = ast, scope) do
    compile_error!(
      "a backfill can't store a list, got: #{Macro.to_string(ast)} - pick one part with at, " <>
        "like #{Macro.to_string(ast)} |> at(0)",
      ast,
      scope
    )
  end

  defp expression({:coalesce, _meta, [_first, _second | _rest] = values}, scope) do
    {:coalesce, Enum.map(values, &expression(&1, scope))}
  end

  defp expression({:count, _meta, [set]}, scope), do: {:count, set(set, :count, scope)}

  defp expression({:most_common, _meta, [set, attribute]}, scope) do
    {:{}, [],
     [
       :most_common,
       set(set, :most_common, scope),
       attribute(attribute, :most_common, scope)
     ]}
  end

  defp expression({stage, _meta, args} = ast, %{in_fn: true} = scope)
       when stage in @stages and is_list(args) do
    compile_error!(
      "a query in a backfill ends in count or most_common, got: #{Macro.to_string(ast)}",
      ast,
      scope
    )
  end

  defp expression({stage, _meta, args} = ast, scope) when stage in @stages and is_list(args) do
    refuse_type_source(ast, scope)
  end

  defp expression(nil, scope) do
    compile_error!(
      "a backfill expression can't hold nil - nil is the absence a backfill exists to fill",
      nil,
      scope
    )
  end

  defp expression(ast, scope) do
    names = path(ast)

    cond do
      constant?(ast) -> {:value, ast}
      names != nil -> {:name, names}
      true -> refuse(ast, scope)
    end
  end

  defp fn_arg({name, _meta, context}, _names, _scope)
       when is_atom(name) and is_atom(context) and name not in [:_ | @special_names] do
    name
  end

  defp fn_arg(ast, _names, scope) do
    compile_error!(
      "a backfill fn takes bare field names as its arguments, got: #{Macro.to_string(ast)}",
      ast,
      scope
    )
  end

  defp fn_args(args, scope) do
    names = Enum.map(args, &fn_arg(&1, args, scope))

    case names -- Enum.uniq(names) do
      [] ->
        names

      [repeated | _rest] ->
        compile_error!("a backfill fn names #{repeated} twice", List.first(args), scope)
    end
  end

  defp fn_kind(body, scope) do
    shape = call_shape(body)

    cond do
      only_constant?(body) -> refuse_constant_fn(body, scope)
      marked_inner(body) != nil -> :marked
      path(body) != nil -> :query
      shape != nil and elem(shape, 0) in @query_calls -> {:word, shape}
      not reads_argument?(body, scope.args, scope.env) -> refuse_constant_fn(body, scope)
      true -> :elixir
    end
  end

  defp fn_parts([{:->, _meta, [[], _body]}], ast, scope), do: refuse_constant_fn(ast, scope)

  defp fn_parts([{:->, _meta, [args, body]}], _ast, scope) do
    {args, fn_args(args, scope), body}
  end

  defp fn_parts(_clauses, ast, scope) do
    compile_error!(
      "a backfill fn has one clause, got: #{Macro.to_string(ast)}",
      ast,
      scope
    )
  end

  # What a query body reads of the row, and the values it pins.
  defp fn_reads({:name, [head | _rest]}), do: {[head], []}

  defp fn_reads({:value, expr}), do: {[], [expr]}

  defp fn_reads({kind, terms}) when kind in [:coalesce, :concat] do
    terms
    |> Enum.map(&fn_reads/1)
    |> Enum.reduce({[], []}, fn {names, values}, {all_names, all_values} ->
      {names ++ all_names, values ++ all_values}
    end)
  end

  defp fn_reads({:count, set}), do: {set_heads(set), []}

  defp fn_reads({:{}, _meta, [:most_common, set, _attribute]}), do: {set_heads(set), []}

  defp fn_reads({:{}, _meta, [:split, text, separator]}) do
    {names, values} = fn_reads(text)
    {[], separator_values} = fn_reads(separator)

    {names, separator_values ++ values}
  end

  defp fn_reads({:{}, _meta, [:at, split, position]}) do
    {names, values} = fn_reads(split)
    {[], position_values} = fn_reads(position)

    {names, position_values ++ values}
  end

  defp guard_of({:when, _meta, args}), do: List.last(args)

  defp guard_of(_pattern), do: nil

  defp interpolated?(parts) do
    Enum.any?(parts, fn
      {:"::", _meta, [{{:., _dot_meta, [Kernel, :to_string]}, _call_meta, _args}, _type]} -> true
      _part -> false
    end)
  end

  defp map_reduce_quote_args([options, block], unquotes, splicing, acc, fun) do
    {options, options_acc} = fun.(options, acc, true, splicing)
    {block, all_acc} = map_reduce_quote_block(block, unquotes, options_acc, fun)

    {[options, block], all_acc}
  end

  defp map_reduce_quote_args(args, unquotes, splicing, acc, fun) do
    Enum.map_reduce(args, acc, fn arg, acc ->
      if Keyword.keyword?(arg) do
        Enum.map_reduce(arg, acc, &map_reduce_quote_option(&1, unquotes, splicing, &2, fun))
      else
        fun.(arg, acc, true, splicing)
      end
    end)
  end

  # With separate options, Elixir takes the first do and ignores the rest. The block is in a quote,
  # so the function splices nothing in it.
  defp map_reduce_quote_block(block, unquotes, acc, fun) do
    if Keyword.keyword?(block) do
      {block, {all_acc, _taken?}} =
        Enum.map_reduce(block, {acc, false}, fn
          {:do, _body} = option, {acc, false} ->
            {option, option_acc} = map_reduce_quote_option(option, unquotes, false, acc, fun)
            {option, {option_acc, true}}

          ignored, state ->
            {ignored, state}
        end)

      {block, all_acc}
    else
      fun.(block, acc, true, false)
    end
  end

  defp map_reduce_quote_option({:do, body}, false, false, acc, _fun), do: {{:do, body}, acc}

  defp map_reduce_quote_option({:do, body}, unquotes, splicing, acc, fun) do
    {body, acc} = map_reduce_unquoted(body, unquotes, splicing, acc, fun)

    {{:do, body}, acc}
  end

  defp map_reduce_quote_option({key, value}, _unquotes, splicing, acc, fun) do
    {value, acc} = fun.(value, acc, true, splicing)

    {{key, value}, acc}
  end

  # Walks the body of a quote for its unquotes, which run as the given unquotes say, unless the
  # function splices them in itself. Unquoted code runs on its own, outside the quote, so the
  # function splices nothing in it. A nested quote keeps its body's unquotes for itself, but its
  # separate options are unquoted (see options_splicing/2).
  defp map_reduce_unquoted({:quote, meta, [options, body]}, unquotes, splicing, acc, fun) do
    options_splicing = options_splicing([options, body], splicing)
    {options, acc} = map_reduce_unquoted(options, unquotes, options_splicing, acc, fun)

    {{:quote, meta, [options, body]}, acc}
  end

  defp map_reduce_unquoted({:quote, _meta, args} = node, _unquotes, _splicing, acc, _fun)
       when is_list(args),
       do: {node, acc}

  defp map_reduce_unquoted({form, _meta, [_value]} = node, _unquotes, splicing, acc, fun)
       when form in [:unquote, :unquote_splicing] and splicing != false,
       do: fun.(node, acc, true, splicing)

  defp map_reduce_unquoted({form, meta, [value]}, unquotes, _splicing, acc, fun)
       when form in [:unquote, :unquote_splicing] do
    {value, acc} = fun.(value, acc, unquotes, false)

    {{form, meta, [value]}, acc}
  end

  defp map_reduce_unquoted(
         {{:., _dot_meta, [_receiver, :unquote]}, _meta, [_value]} = node,
         _unquotes,
         splicing,
         acc,
         fun
       )
       when splicing != false,
       do: fun.(node, acc, true, splicing)

  # Elixir has no remote unquote_splicing, and the receiver is still unquoted.
  defp map_reduce_unquoted(
         {{:., dot_meta, [receiver, :unquote]}, meta, [value]},
         unquotes,
         splicing,
         acc,
         fun
       ) do
    {receiver, receiver_acc} = map_reduce_unquoted(receiver, unquotes, splicing, acc, fun)
    {value, all_acc} = fun.(value, receiver_acc, unquotes, false)

    {{{:., dot_meta, [receiver, :unquote]}, meta, [value]}, all_acc}
  end

  defp map_reduce_unquoted({form, meta, args}, unquotes, splicing, acc, fun) do
    {[form, args], acc} = map_reduce_unquoted([form, args], unquotes, splicing, acc, fun)

    {{form, meta, args}, acc}
  end

  defp map_reduce_unquoted({left, right}, unquotes, splicing, acc, fun) do
    {[left, right], acc} = map_reduce_unquoted([left, right], unquotes, splicing, acc, fun)

    {{left, right}, acc}
  end

  defp map_reduce_unquoted(list, unquotes, splicing, acc, fun) when is_list(list) do
    Enum.map_reduce(list, acc, &map_reduce_unquoted(&1, unquotes, splicing, &2, fun))
  end

  defp map_reduce_unquoted(other, _unquotes, _splicing, acc, _fun), do: {other, acc}

  # What query(...) wraps, in a tuple since the wrapped expression can be nil, or nil when the body
  # isn't marked.
  defp marked_inner({:query, _meta, [inner]}), do: {inner}

  defp marked_inner({:|>, _meta, [left, {:query, _call_meta, []}]}), do: {left}

  defp marked_inner(_body), do: nil

  defp only_constant?({form, _meta, _args}) when form in [:@, :^], do: true

  defp only_constant?(ast), do: constant?(ast)

  defp op_backfills(%{op: kind} = op) when kind in @backfill_ops do
    op
    |> Map.take([:changes, :opts])
    |> Map.values()
    |> Enum.flat_map(&option_backfills/1)
  end

  defp op_backfills(_op), do: []

  defp operands({:<>, _meta, [left, right]}, scope) do
    operands(left, scope) ++ operands(right, scope)
  end

  defp operands(ast, scope), do: [expression(ast, scope)]

  defp operator_call?({name, arity}), do: Macro.operator?(name, arity)

  defp operator_call?(nil), do: false

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

  # The function leaves a quote's args as written, so it splices nothing in them, except in
  # separate options. Elixir looks for unquotes to splice everywhere but there, so it splices
  # there only when the function has another unquote.
  defp options_splicing([_options, _block], false), do: false

  defp options_splicing([_options, _block], _splicing), do: :unknown

  defp options_splicing(_args, _splicing), do: false

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

  defp pattern_variables(pattern) do
    {_ast, names} =
      pattern
      |> without_guards()
      |> Macro.prewalk([], fn
        {:^, _meta, _args}, found ->
          {nil, found}

        # A segment's size reads a value rather than binding one.
        {:"::", meta, [value, _spec]}, found ->
          {{:__block__, meta, [value]}, found}

        {name, _meta, context} = node, found when is_atom(name) and is_atom(context) ->
          {node, [name | found]}

        node, found ->
          {node, found}
      end)

    names
  end

  # The names a pinned expression binds itself, which aren't the row's. One it also reads from
  # outside its binding is unbound where the pin runs, so the compiler refuses it.
  defp pin_bindings(expr, env) do
    {_ast, names} =
      Macro.prewalk(expr, [], fn
        # A cond's heads are expressions, whatever the arrows around them look like.
        {:cond, _meta, [[do: _clauses]]} = node, found ->
          {without_pattern(node, env), found}

        {kind, _meta, [pattern, _right]} = node, found
        when kind in [:->, :<-, :=, :destructure, :match?] ->
          {node, Enum.concat(pattern_variables(pattern), found)}

        {{:., _dot_meta, [receiver, form]}, _meta, [pattern, _right]} = node, found
        when form in [:destructure, :match?] ->
          if Macro.expand(receiver, env) == Kernel do
            {node, Enum.concat(pattern_variables(pattern), found)}
          else
            {node, found}
          end

        # In a bitstring generator only the last segment sits inside the <- node.
        {:<<>>, _meta, [_first | _rest] = parts} = node, found ->
          if match?({:<-, _arrow_meta, _args}, List.last(parts)) do
            {node, Enum.concat(pattern_variables(Enum.drop(parts, -1)), found)}
          else
            {node, found}
          end

        node, found ->
          {node, found}
      end)

    names
  end

  # A pin in a pattern matches against a variable, which Elixir allows anywhere in a body.
  defp pin_outside_pattern?(ast, env) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn node, found? ->
        kept =
          node
          |> unpiped_call(env)
          |> without_pattern(env)

        {kept, found? or match?({:^, _meta, _args}, kept)}
      end)

    found?
  end

  # What a pipe can go into: a word or a remote call, which then refuses on its own terms.
  defp pipeable?(form, _args) when not is_atom(form), do: true

  defp pipeable?(form, args) do
    form not in [:^, :|>, :<<>>, :__block__ | @value_forms] and not sigil?(form) and
      not Macro.operator?(form, length(args))
  end

  defp position({:^, _meta, [expr]}, _scope), do: {:value, expr}

  defp position(n, _scope) when is_integer(n) and n in 0..@max_position, do: {:value, n}

  defp position({:+, _meta, [n]}, _scope) when is_integer(n) and n in 0..@max_position do
    {:value, n}
  end

  defp position({:-, _meta, [0]}, _scope), do: {:value, 0}

  defp position({:-, _meta, [n]} = ast, scope) when is_integer(n) do
    compile_error!(
      "at counts from 0, got: #{Macro.to_string(ast)} - it can't count from the end yet",
      ast,
      scope
    )
  end

  defp position(ast, scope) do
    compile_error!(
      "at takes a position from 0 to #{@max_position} or a pinned expression, " <>
        "got: #{Macro.to_string(ast)}",
      ast,
      scope
    )
  end

  defp prepend_fill(acc, op, model, next_model) do
    case op_backfills(op) do
      [] ->
        acc

      [backfill | _rest] ->
        {kind, member} = fill_member(op, next_model)

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

  # Whether a quote with the given args unquotes its body: true or false as its options spell it,
  # or :unknown when only the compiler can read them, like an attribute. With separate options,
  # Elixir ignores any beside the do.
  defp quote_unquotes(args) do
    written =
      case args do
        [first, _block] -> first
        [single] -> single
        _other -> []
      end

    settings = if Keyword.keyword?(written), do: written, else: [unquote: written]

    case Keyword.get(settings, :unquote, not Keyword.has_key?(settings, :bind_quoted)) do
      setting when is_boolean(setting) -> setting
      _compiler_read -> :unknown
    end
  end

  defp read_query(_body, :elixir, _scope), do: :none

  defp read_query(body, kind, scope) do
    inner = if kind == :marked, do: elem(marked_inner(body), 0), else: body
    term = expression(inner, scope)

    validate_fn_term!(term, inner, scope)

    {:ok, term}
  rescue
    error in Hologram.CompileError -> {:error, error}
  end

  # A module attribute is a value of the file rather than a read of the row.
  defp reads_argument?(ast, args, env) do
    {_ast, found?} =
      ast
      |> Macro.prewalk(&unpiped_call(&1, env))
      |> Macro.prewalk(false, fn
        {:@, _meta, _args}, found? ->
          {nil, found?}

        # A capture's name is a function, whatever variable shares it.
        {:&, _meta, [{:/, _slash_meta, [{_name, _name_meta, context}, arity]}]}, found?
        when is_atom(context) and is_integer(arity) ->
          {nil, found?}

        {name, _meta, context} = node, found? when is_atom(name) and is_atom(context) ->
          {node, found? or name in args}

        node, found? ->
          {node, found?}
      end)

    found?
  end

  # The rows of an entity type pointing at this one, the query shape a fn can read.
  defp referencing({:filter, _meta, [source, condition]} = ast, scope) do
    case {unpipe(source, scope), condition} do
      {{:__aliases__, _alias_meta, [head | _rest]} = type, _condition} when not is_atom(head) ->
        compile_error!(
          "a backfill fn names the type it queries by its module, got: " <>
            "#{Macro.to_string(type)} - write the module out",
          type,
          scope
        )

      {{:__aliases__, _alias_meta, _segments} = type,
       {:==, _eq_meta,
        [{field, _field_meta, context}, {:^, _pin_meta, [{:id, _id_meta, id_context}]}]}}
      when is_atom(field) and is_atom(context) and is_atom(id_context) ->
        referencing_set(type, field, ast, scope)

      _other_shape ->
        refuse_referencing(ast, scope)
    end
  end

  defp referencing(ast, scope), do: refuse_referencing(ast, scope)

  # The name comes from the migration's own source, so it's bounded by the file.
  # sobelow_skip ["DOS.StringToAtom"]
  defp referencing_set(type, field, ast, scope) do
    text = Atom.to_string(field)

    if String.ends_with?(text, "_id") and :id in scope.args do
      ref =
        text
        |> String.replace_suffix("_id", "")
        # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
        |> String.to_atom()

      {:{}, [], [:referencing, type, ref]}
    else
      refuse_referencing(ast, scope)
    end
  end

  @spec refuse(Macro.t(), scope) :: no_return
  defp refuse({word, _meta, args} = ast, scope) when word in @words and is_list(args) do
    compile_error!(
      "#{word} takes #{Map.fetch!(@word_arguments, word)}, got: #{Macro.to_string(ast)}",
      ast,
      scope
    )
  end

  defp refuse({:<<>>, _meta, parts} = ast, scope) do
    if interpolated?(parts) do
      compile_error!(
        "a backfill joins strings with <>, got: #{Macro.to_string(ast)} - " <>
          ~s(write it like "Trip to " <> destination),
        ast,
        scope
      )
    else
      refuse_unpinned(ast, scope)
    end
  end

  defp refuse({name, _meta, args} = ast, scope)
       when is_atom(name) and is_list(args) and name not in @value_forms do
    if sigil?(name) do
      refuse_unpinned(ast, scope)
    else
      compile_error!(
        "#{name}/#{length(args)} is no backfill word - the words are <>, split, at, coalesce, " <>
          "count and most_common, and a value from the surrounding code is pinned with ^",
        ast,
        scope
      )
    end
  end

  defp refuse(ast, scope), do: refuse_unpinned(ast, scope)

  @spec refuse_capture(Macro.t(), scope) :: no_return
  defp refuse_capture(ast, scope) do
    compile_error!(
      "a backfill takes no capture, got: #{Macro.to_string(ast)} - a capture hides the fields " <>
        "it reads, so write a fn naming them",
      ast,
      scope
    )
  end

  @spec refuse_constant_fn(Macro.t(), scope) :: no_return
  defp refuse_constant_fn(ast, scope) do
    compile_error!(
      "a backfill fn reads the row, got: #{Macro.to_string(ast)} - for one value for every " <>
        "row, write it without the fn, like backfill: ^@default",
      ast,
      scope
    )
  end

  @spec refuse_fn(Macro.t(), scope) :: no_return
  defp refuse_fn(ast, scope) do
    compile_error!(
      "a fn goes at the top of backfill:, got one inside the expression: " <>
        Macro.to_string(ast),
      ast,
      scope
    )
  end

  @spec refuse_pipe(Macro.t(), Macro.t(), scope) :: no_return
  defp refuse_pipe(right, ast, scope) do
    compile_error!(
      "a backfill pipes into a word called with parentheses, got: #{Macro.to_string(right)}",
      ast,
      scope
    )
  end

  @spec refuse_referencing(Macro.t(), scope) :: no_return
  defp refuse_referencing(ast, scope) do
    compile_error!(
      "a backfill fn queries the rows pointing at this one, written Type |> filter(ref_id == " <>
        "^id) with id among the fn's arguments, got: #{Macro.to_string(ast)}",
      ast,
      scope
    )
  end

  @spec refuse_set(Macro.t(), atom, scope) :: no_return
  defp refuse_set(atom, word, scope) when is_atom(atom) and atom not in [nil, true, false] do
    compile_error!(
      "#{word} names the relationship with a bare name, got: #{inspect(atom)} - write #{atom}",
      atom,
      scope
    )
  end

  defp refuse_set(ast, word, scope) do
    compile_error!(
      "#{word} takes a relationship of the row, got: #{Macro.to_string(ast)}",
      ast,
      scope
    )
  end

  @spec refuse_type_source(Macro.t(), scope) :: no_return
  defp refuse_type_source(ast, scope) do
    compile_error!(
      "a backfill without a fn reads the row's own relationships, got: " <>
        "#{Macro.to_string(ast)} - for the rows pointing at this one, write a fn naming its " <>
        "id, like fn id -> Stop |> filter(trip_id == ^id) |> count() end",
      ast,
      scope
    )
  end

  @spec refuse_unpinned(Macro.t(), scope) :: no_return
  defp refuse_unpinned(ast, scope) do
    spelled = Macro.to_string(ast)

    compile_error!(
      "a backfill expression can't read #{spelled} - a value from the surrounding code is " <>
        "pinned: ^#{spelled}",
      ast,
      scope
    )
  end

  @spec refuse_word_in_elixir!({atom, non_neg_integer}, Macro.t(), scope) :: no_return
  defp refuse_word_in_elixir!({:split, _arity}, body, scope) do
    compile_error!(
      "split is a query word, and this fn's body is Elixir - write String.split/2",
      body,
      scope
    )
  end

  defp refuse_word_in_elixir!({:at, _arity}, body, scope) do
    compile_error!(
      "at is a query word, and this fn's body is Elixir - write Enum.at/2",
      body,
      scope
    )
  end

  defp refuse_word_in_elixir!({word, _arity}, body, scope) do
    compile_error!(
      "#{word} is a query word, and this fn's body is Elixir, which reads only the row's own " <>
        "fields and has no query - write the whole body in Elixir, or the whole body in query " <>
        "words",
      body,
      scope
    )
  end

  defp resolved_backfill(%__MODULE__{} = value, op, kind, member, model) do
    {:computed, resolve!(value, model, op.entity, fill_target(kind, member, op))}
  end

  defp resolved_backfill(value, _op, :relationship, _member, _model) do
    {:constant, normalize_constant(value, :uuid)}
  end

  defp resolved_backfill(value, _op, :attribute, {_name, type, _opts}, _model) do
    {:constant, normalize_constant(value, type)}
  end

  # What the code runs: pipes expanded, and a quote reduced to the code it runs, since its own
  # code is data. Code only the compiler can tell runs, like under quote options an attribute
  # holds, is left to the compiler, or kept with the given :may_run.
  defp run_code(expr, env, which \\ :runs), do: run_code(expr, env, true, which)

  defp run_code({_form, meta, args} = node, env, splicing, which) when is_list(args) do
    case map_reduce_quote(node, env, splicing, [], &run_quote_code(&1, &2, &3, &4, env, which)) do
      {:ok, _quote, code} ->
        {:__block__, meta, Enum.reverse(code)}

      :error ->
        case unpiped_call(node, env) do
          ^node ->
            {form, meta, args} = node

            {run_code(form, env, splicing, which), meta, run_code(args, env, splicing, which)}

          unpiped ->
            run_code(unpiped, env, splicing, which)
        end
    end
  end

  defp run_code({left, right}, env, splicing, which) do
    {run_code(left, env, splicing, which), run_code(right, env, splicing, which)}
  end

  defp run_code(list, env, splicing, which) when is_list(list) do
    Enum.map(list, &run_code(&1, env, splicing, which))
  end

  defp run_code(other, _env, _splicing, _which), do: other

  defp run_quote_code(code, found, runs, splicing, env, which)
       when runs == true or which == :may_run do
    {code, [run_code(code, env, splicing, which) | found]}
  end

  defp run_quote_code(code, found, :unknown, _splicing, _env, :runs), do: {code, found}

  defp segment_sizes({:-, _meta, [left, right]}) do
    left
    |> segment_sizes()
    |> Enum.concat(segment_sizes(right))
  end

  defp segment_sizes({:*, _meta, [size, _unit]}), do: [size]

  defp segment_sizes({:size, _meta, [size]}), do: [size]

  defp segment_sizes(_spec), do: []

  defp separator({:^, _meta, [expr]}, _scope), do: {:value, expr}

  defp separator("", scope) do
    compile_error!("split takes a non-empty separator, got: \"\"", "", scope)
  end

  defp separator(separator, _scope) when is_binary(separator), do: {:value, separator}

  defp separator(ast, scope) do
    compile_error!(
      "split takes a string separator or a pinned expression, got: #{Macro.to_string(ast)}",
      ast,
      scope
    )
  end

  defp set(ast, word, scope) do
    unpiped = unpipe(ast, scope)

    cond do
      type_source?(unpiped, scope) and scope.in_fn -> referencing(unpiped, scope)
      type_source?(unpiped, scope) -> refuse_type_source(unpiped, scope)
      names = path(unpiped) -> {:relationship, names}
      true -> refuse_set(unpiped, word, scope)
    end
  end

  defp set_heads({:relationship, [head | _rest]}), do: [head]

  # Reads the row's id, the argument its filter pins.
  defp set_heads({:{}, _meta, [:referencing, _type, _ref]}), do: [:id]

  # An Elixir body gets the row's values as its arguments, so a query word or a pin in it has
  # nothing to read.
  defp settle_elixir!(reading, module) do
    scope = %{args: reading.args, env: reading.env, in_fn: true}

    if not reads_argument?(reading.body, reading.args, reading.env) do
      refuse_constant_fn(reading.body, scope)
    end

    validate_no_scope_change!(reading.body, scope)
    validate_no_own_macros!(reading, module, scope)
    validate_no_words!(reading, module, scope)

    if pin_outside_pattern?(run_code(reading.body, reading.env, :may_run), reading.env) do
      compile_error!(
        "an Elixir backfill fn gets the row's values as its arguments, so it pins nothing, " <>
          "got: #{Macro.to_string(reading.body)} - read the argument by name, and a module " <>
          "attribute as @x",
        reading.body,
        scope
      )
    end

    :elixir
  end

  defp settle_query!(%{query: {:ok, _term}}), do: :query

  defp settle_query!(%{query: {:error, error}}), do: raise(error)

  defp sigil?(name) do
    name
    |> Atom.to_string()
    |> String.starts_with?("sigil_")
  end

  defp split(ast, scope) do
    case unpipe(ast, scope) do
      {:split, _meta, [text, separator]} ->
        {:{}, [], [:split, expression(text, scope), separator(separator, scope)]}

      other ->
        compile_error!(
          "at reads a part of a split, got: #{Macro.to_string(other)}",
          other,
          scope
        )
    end
  end

  # Whether the given set is a query rather than a relationship of the row: an entity type, or
  # query stages, whatever they start from.
  defp type_source?({:__aliases__, _meta, _segments}, _scope), do: true

  defp type_source?({stage, _meta, [source | _rest]}, scope) when stage in @stages do
    stage == :filter or
      source
      |> unpipe(scope)
      |> type_source?(scope)
  end

  defp type_source?(_ast, _scope), do: false

  defp unpipe({:|>, _meta, [left, {form, call_meta, args} = right]} = ast, scope)
       when is_list(args) do
    if pipeable?(form, args) do
      {form, call_meta, [left | args]}
    else
      refuse_pipe(right, ast, scope)
    end
  end

  defp unpipe({:|>, _meta, [_left, right]} = ast, scope), do: refuse_pipe(right, ast, scope)

  defp unpipe(ast, _scope), do: ast

  # A pipe is the call Elixir expands it to, however it's spelled, but only Kernel's pipe expands:
  # a migration's own |> is a call whose right side is a value, and any other receiver stays read.
  defp unpiped_call({{:., _dot_meta, [receiver, :|>]}, meta, [left, right]} = node, env) do
    if Macro.expand(receiver, env) == Kernel do
      expanded_pipe({:|>, meta, [left, right]}, env)
    else
      node
    end
  end

  # A quote's call names the import it was written with, which Elixir takes over the env it
  # expands in.
  defp unpiped_call({:|>, meta, [_left, _right]} = pipe, env) do
    quoted_import =
      if Keyword.has_key?(meta, :context), do: List.keyfind(meta[:imports] || [], 2, 0)

    kernel? =
      case quoted_import do
        {2, module} -> module == Kernel
        nil -> Macro.Env.lookup_import(env, {:|>, 2}) == [macro: Kernel]
      end

    if kernel?, do: expanded_pipe(pipe, env), else: pipe
  end

  defp unpiped_call(node, _env), do: node

  # The resolver checks a value's args, and a function term runs on its own, so they must agree.
  defp function_args_match?({:function, _module, _function, term_args}, args),
    do: term_args == args

  defp function_args_match?(_term, _args), do: true

  defp valid_args?(args),
    do: is_list(args) and not List.improper?(args) and Enum.all?(args, &is_atom/1)

  defp valid_list?(list, min_length) do
    is_list(list) and not List.improper?(list) and length(list) >= min_length
  end

  defp valid_name?(names), do: valid_list?(names, 1) and Enum.all?(names, &is_atom/1)

  defp valid_operand?({:concat, _operands}), do: false

  defp valid_operand?(operand), do: valid_term?(operand)

  defp valid_set?({:relationship, names}), do: valid_name?(names)

  defp valid_set?({:referencing, type, ref}), do: is_atom(type) and is_atom(ref)

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

  # A function reading nothing of the row would be a constant, which the op holds as one.
  defp valid_top_term?({:function, function_module, function, args}, module, backfill_functions) do
    module != nil and function_module == module and args != [] and
      {module, function, args} in backfill_functions and
      function_exported?(module, function, length(args))
  end

  defp valid_top_term?(term, _module, _backfill_functions), do: valid_term?(term)

  # A term reading nothing of the row is a constant, and a name that isn't an argument, or an
  # argument pinned, would read the surrounding code.
  # A body can read a field more than once, and list subtraction takes away only one copy.
  defp validate_fn_term!(term, inner, scope) do
    {names, values} = fn_reads(term)

    Enum.each(values, &validate_pin!(&1, inner, scope))

    if names == [], do: refuse_constant_fn(inner, scope)

    case Enum.uniq(names) -- scope.args do
      [] ->
        :ok

      [name | _rest] ->
        compile_error!(
          "a backfill fn reads #{name}, which isn't among its arguments - add it: " <>
            "fn #{Enum.join(Enum.concat(scope.args, [name]), ", ")} -> ...",
          inner,
          scope
        )
    end
  end

  # An import written below the op is in force where a body is emitted but not where it's read, so
  # the same call would mean two things.
  defp validate_imports_agree!(reading, env) do
    moved =
      Enum.find(reading.calls, fn call ->
        elixir_imports(reading.env, call) != elixir_imports(env, call)
      end)

    if moved do
      {name, arity} = moved

      Expression.compile_error!(
        "a backfill fn calls #{name}/#{arity}, which an import changes between the op and the " <>
          "end of the module - put the import at the top of the module",
        reading.body,
        reading.env
      )
    end
  end

  # A macro of the migration can expand to an alias or an import the check above can't see, and
  # an attribute it returns reads the value assigned last, since the body is placed at the end of
  # the module. Any other module's macro is refused by the call check. A guard is expanded where
  # it's defined, so it can do neither (see own_macro/2).
  defp validate_no_own_macros!(reading, module, scope) do
    macro =
      reading.body
      |> may_run_calls(reading.env)
      |> own_macro(module)

    if macro do
      {name, arity} = macro

      compile_error!(
        "an Elixir backfill fn can't call the migration's macro #{name}/#{arity} - make it a " <>
          "defp, or a defguardp in a guard",
        reading.body,
        scope
      )
    end
  end

  # An Elixir body's aliases are expanded where the op is written, and its calls judged by the
  # imports there, so one it changes for itself would run another function than the one written.
  # Quoted code changes nothing, but an unquote can splice one in unseen. The unquotes the
  # function the body runs in splices in itself are refused where the op is written (see
  # Hologram.Migration), and a quote's own unquote is refused here too, so that no unquote has to
  # be told apart.
  defp validate_no_scope_change!(body, scope) do
    {_ast, unquoted} =
      body
      |> Macro.prewalk(&unpiped_call(&1, scope.env))
      |> Macro.prewalk(nil, fn
        {form, _meta, args} = node, nil
        when form in [:unquote, :unquote_splicing] and is_list(args) ->
          {node, form}

        # A remote unquote splices in the function's name, piped too.
        {{:., _dot_meta, [_receiver, :unquote]}, _meta, args} = node, nil when is_list(args) ->
          {node, :unquote}

        node, found ->
          {node, found}
      end)

    {_ast, changed} =
      body
      |> run_code(scope.env)
      |> Macro.prewalk(unquoted, fn
        {kind, _meta, args} = node, nil when kind in @scope_changing_forms and is_list(args) ->
          {node, kind}

        node, found ->
          {node, found}
      end)

    case changed do
      nil ->
        :ok

      kind when kind in [:unquote, :unquote_splicing] ->
        compile_error!(
          "an Elixir backfill fn can't #{kind} inside its body - read a value of the file as @x",
          body,
          scope
        )

      kind ->
        compile_error!(
          "an Elixir backfill fn can't #{kind} inside its body - put the #{kind} at the top of " <>
            "the module",
          body,
          scope
        )
    end
  end

  defp validate_no_words!(reading, module, scope) do
    if {:query, 1} in reading.run_calls do
      compile_error!(
        "query(...) wraps the whole body of a backfill fn, got: " <>
          Macro.to_string(reading.body),
        reading.body,
        scope
      )
    end

    words =
      Enum.filter(reading.run_calls, fn {name, _arity} = call ->
        name in @elixir_refused_words and not call_taken?(call, reading, module)
      end)

    if words != [] and operator_call?(call_shape(reading.body)) and
         match?({:ok, _term}, read_query(reading.body, :query, scope)) do
      compile_error!(
        "a backfill fn mixes an operator with query words, got: " <>
          "#{Macro.to_string(reading.body)} - wrap the whole body in query(...)",
        reading.body,
        scope
      )
    end

    case words do
      [word | _rest] -> refuse_word_in_elixir!(word, reading.body, scope)
      [] -> :ok
    end
  end

  defp validate_pin!(expr, inner, scope) do
    code = run_code(expr, scope.env)
    readable = scope.args -- pin_bindings(code, scope.env)

    {_ast, pinned} =
      Macro.prewalk(code, [], fn
        {:@, _meta, _args}, found ->
          {nil, found}

        # A capture's name is a function, whatever variable shares it.
        {:&, _meta, [{:/, _slash_meta, [{_name, _name_meta, context}, arity]}]}, found
        when is_atom(context) and is_integer(arity) ->
          {nil, found}

        # A segment's type is a word, so only its value and size are read.
        {:"::", meta, [value, spec]}, found ->
          {{:__block__, meta, [value | segment_sizes(spec)]}, found}

        {name, _meta, context} = node, found when is_atom(name) and is_atom(context) ->
          {node, if(name in readable, do: [name | found], else: found)}

        node, found ->
          {node, found}
      end)

    case pinned do
      [] ->
        :ok

      [name | _rest] ->
        compile_error!(
          "a backfill fn reads its argument #{name} by name, not pinned - write #{name}",
          inner,
          scope
        )
    end
  end

  defp value_ast(term, args) do
    {:%{}, [], [__struct__: __MODULE__, args: args, term: term]}
  end

  # A cond's heads are expressions, so they stay in the walk with the clauses taken apart.
  defp without_guards(body) do
    Macro.prewalk(body, fn
      {:when, meta, args} -> {:__block__, meta, Enum.drop(args, -1)}
      node -> node
    end)
  end

  defp without_pattern(
         {:cond, meta, [[do: [{:->, _arrow_meta, _args} | _rest] = clauses]]},
         _env
       ) do
    {:cond, meta, [Enum.flat_map(clauses, fn {:->, _meta, [heads, body]} -> [body | heads] end)]}
  end

  # In a bitstring generator every segment before the <- is pattern too.
  defp without_pattern({:<<>>, meta, [_first | _rest] = parts} = node, _env) do
    case List.last(parts) do
      {:<-, _arrow_meta, [pattern, right]} -> {:__block__, meta, [guard_of(pattern), right]}
      _segment -> node
    end
  end

  # Kernel.destructure/2 matches its first argument against the list it pads, so that's a pattern.
  defp without_pattern({op, meta, [pattern, right]}, _env)
       when op in [:=, :<-, :match?, :destructure] do
    {op, meta, [guard_of(pattern), right]}
  end

  defp without_pattern({:->, meta, [heads, body]}, _env) do
    {:->, meta, [Enum.map(heads, &guard_of/1), body]}
  end

  defp without_pattern(
         {{:., _dot_meta, [receiver, name]} = form, meta, [pattern, right]} = node,
         env
       )
       when name in [:match?, :destructure] do
    if Macro.expand(receiver, env) == Kernel,
      do: {form, meta, [guard_of(pattern), right]},
      else: node
  end

  defp without_pattern(node, _env), do: node
end
