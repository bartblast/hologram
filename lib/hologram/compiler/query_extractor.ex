defmodule Hologram.Compiler.QueryExtractor do
  @moduledoc false

  alias Hologram.Commons.PLT
  alias Hologram.Compiler
  alias Hologram.Compiler.IR
  alias Hologram.Entity.Derived
  alias Hologram.Entity.Derived.RowRef
  alias Hologram.MisuseError
  alias Hologram.Query
  alias Hologram.Query.RowField
  alias Hologram.Query.Stage
  alias Hologram.Reflection

  # The applications shipped with Elixir itself - their modules are never followed into, so a field
  # of the row reaching them is refused naming the call the developer wrote instead of its
  # internals, and they never count among the modules whose edits can change a definition.
  @elixir_apps [:eex, :elixir, :ex_unit, :iex, :logger, :mix]

  # The modules a derived field's walk followed calls into or ran functions of, gathered across the
  # closures it runs, which start from states of their own.
  @derived_reads_key {__MODULE__, :derived_reads}

  # The expressions a derived field's walk built from the row: strings joined, a value a condition
  # picks, whether a condition holds. Each is a plain tuple of lowered names, so nothing in its
  # shape tells it from a tuple the builder wrote, and the walk remembers the ones it built.
  @row_expressions_key {__MODULE__, :row_expressions}

  @row_expression_functions [:concat, :condition, :if_value]

  @doc """
  Resolves the definition of the given derived field of the given entity type by walking the
  field's clause of the type's `__derived_definition__/1` over its IR - the way a body calling a
  query builder is resolved, since the builder is written for the values it will be given, and a
  field of the row has none while the definition is built.

  What the walk reads stands in for the row's fields as `Hologram.Entity.Derived.field/2` builds
  them - a query over a set, a row field, a related row - and goes where a query goes: query stages
  and `Hologram.Entity.Derived` run natively over them, a call into the entity type's own functions
  or another module of the project is followed into its IR with them, and a dot on a related row
  reads the longer path. The result is normalized as `Hologram.Entity.Derived.resolve/2` normalizes it, and returned with the modules
  whose functions the walk followed - the ones whose edits can change it besides the entity types'.
  A branch on a value the build knows takes the clause that value takes.

  Raises Hologram.CompileError, located where the walk stood, when the definition can't be resolved:
  among others, when a branch depends on a field of the row, when a field of the row reaches
  anything but a query stage, `Hologram.Entity.Derived` or a query builder, when a builder the body
  calls returns no query term or is no module of the project, when a known value matches no clause,
  when a call is recursive or undefined, when a query stage or `Hologram.Entity.Derived` refuses
  what it is given, and when the body uses a construct the walk doesn't cover yet.
  """
  @spec derived_definition(module, atom, PLT.t()) :: {Derived.definition(), list(module)}
  def derived_definition(entity_type, name, ir_plt) do
    {file, line} = Map.fetch!(entity_type.__derived_locations__(), name)

    context = %{
      current_module: entity_type,
      derived: %{at_field?: true, file: file},
      ir_plt: ir_plt,
      line: line,
      stack: [{entity_type, :__derived_definition__, 1, [file: file, line: line]}],
      subject: "derived field #{inspect(name)} in #{inspect(entity_type)}"
    }

    clause = derived_clause!(entity_type, name, ir_plt)

    Process.put(@derived_reads_key, MapSet.new())
    Process.put(@row_expressions_key, MapSet.new())

    try do
      # Every branch of a derived field's walk is decided or refused, so the walk builds one
      # definition.
      {definition, _state} = evaluate!(clause.body, %{env: %{}, funs_cache: %{}}, context)

      read_modules =
        @derived_reads_key
        |> Process.get()
        |> Enum.sort()

      {Derived.normalize(definition), read_modules}
    after
      Process.delete(@derived_reads_key)
      Process.delete(@row_expressions_key)
    end
  end

  defp anonymous_closure!(1, clause, closure_env, context) do
    fn arg_1 -> interpret_anonymous!(clause, [arg_1], closure_env, context) end
  end

  defp anonymous_closure!(2, clause, closure_env, context) do
    fn arg_1, arg_2 -> interpret_anonymous!(clause, [arg_1, arg_2], closure_env, context) end
  end

  defp anonymous_closure!(3, clause, closure_env, context) do
    fn arg_1, arg_2, arg_3 ->
      interpret_anonymous!(clause, [arg_1, arg_2, arg_3], closure_env, context)
    end
  end

  defp anonymous_closure!(arity, _clause, _closure_env, context) do
    compile_error!(
      "#{context.subject} uses an anonymous function of arity #{arity} - only arities 1-3 can be resolved at build time yet",
      context
    )
  end

  # A stage call the developer wrote is theirs to read, so a refusal from it is reraised carrying
  # the derived field it belongs to, which the error cannot know.
  defp apply_authored_stage!(function, arg_values, context) do
    apply(Stage, function, arg_values)
  rescue
    error in [ArgumentError, MisuseError] ->
      reraise Hologram.CompileError,
              [
                message:
                  "#{context.subject} builds an invalid query - #{Exception.message(error)}",
                file: context_file(context),
                line: context.line,
                stack: context.stack
              ],
              __STACKTRACE__
  end

  # A Derived call builds a stand-in or a definition from others, so it runs natively - what it
  # refuses is the definition's to answer for, at the line the walk stood on.
  defp apply_derived!(function, arg_values, context) do
    result = apply(Derived, function, arg_values)

    if function in @row_expression_functions do
      Process.put(@row_expressions_key, MapSet.put(row_expressions(), result))
    end

    result
  rescue
    error in [ArgumentError, MisuseError] ->
      reraise Hologram.CompileError,
              [
                message:
                  "#{context.subject} builds an invalid definition - #{Exception.message(error)}",
                file: context_file(context),
                line: context.line,
                stack: context.stack
              ],
              __STACKTRACE__
  end

  defp bound_again(bound, value, outcome, bindings) do
    cond do
      stand_in?(bound) or stand_in?(value) -> {:cont, {:unknown, bindings}}
      bound === value -> {:cont, {outcome, bindings}}
      true -> {:halt, :no_match}
    end
  end

  # A variable a head names twice binds one value, so the second binding has to equal the first, as
  # Elixir matches it - unknown when either value is.
  defp bound_together(bindings, new_bindings) do
    Enum.reduce_while(new_bindings, {:match, bindings}, fn {key, value}, {outcome, acc} ->
      case Map.fetch(acc, key) do
        :error -> {:cont, {outcome, Map.put(acc, key, value)}}
        {:ok, bound} -> bound_again(bound, value, outcome, acc)
      end
    end)
  end

  # A call the field's own clause makes, local or into another module, is a query builder: followed
  # into its IR, whatever it is given, since it builds the query the definition is - so it returns a
  # query term.
  defp builder_call!(module, function, arg_values, state, context) do
    spelled = "#{inspect(module)}.#{function}/#{length(arg_values)}"

    if not interpretable_module?(module) do
      compile_error!(
        "#{context.subject} calls #{spelled}, which the build cannot follow - a query builder is a module of the project",
        context
      )
    end

    {value, state_after_call} = interpret_call!(module, function, arg_values, state, context)

    if not is_struct(value, Query) do
      compile_error!(
        "#{context.subject} calls #{spelled}, which returns #{inspect(value)} - a builder builds a query, and a value computed from fields is written in the derived field's own body",
        context
      )
    end

    {value, state_after_call}
  end

  defp call_binding!(%IR.Variable{name: name, version: version}, value, _context),
    do: {{name, version}, value}

  defp call_binding!(%IR.AtomType{}, _value, _context), do: nil

  defp call_binding!(%IR.FloatType{}, _value, _context), do: nil

  defp call_binding!(%IR.IntegerType{}, _value, _context), do: nil

  defp call_binding!(%IR.MatchPlaceholder{}, _value, _context), do: nil

  defp call_binding!(%IR.StringType{}, _value, _context), do: nil

  defp call_binding!(_param_ir, _value, context) do
    compile_error!(
      "#{context.subject} calls a function whose head destructures a parameter - only plain names, literals, and _ can be resolved at build time yet",
      context
    )
  end

  defp call_env!(params, arg_values, base_env, context) do
    params
    |> Enum.zip(arg_values)
    |> Enum.reduce(base_env, fn {param_ir, value}, env ->
      case call_binding!(param_ir, value, context) do
        {name, bound_value} -> Map.put(env, name, bound_value)
        nil -> env
      end
    end)
  end

  defp case_clause_env!(
         %IR.Variable{name: name, version: version},
         condition_value,
         env,
         _context
       ) do
    Map.put(env, {name, version}, condition_value)
  end

  defp case_clause_env!(%IR.AtomType{}, _condition_value, env, _context), do: env

  defp case_clause_env!(%IR.FloatType{}, _condition_value, env, _context), do: env

  defp case_clause_env!(%IR.IntegerType{}, _condition_value, env, _context), do: env

  defp case_clause_env!(%IR.MatchPlaceholder{}, _condition_value, env, _context), do: env

  defp case_clause_env!(%IR.StringType{}, _condition_value, env, _context), do: env

  defp case_clause_env!(_pattern_ir, _condition_value, _env, context) do
    compile_error!(
      "#{context.subject} uses a composite case pattern - only variables, literals, and _ can be resolved at build time yet",
      context
    )
  end

  # The clause a branch takes: the one candidate. With none, the code raises where the branch is,
  # and with more the build cannot tell which, so the branch is refused.
  defp choose_clause!([], no_match, context), do: compile_error!(no_match, context)

  defp choose_clause!([index], _no_match, _context), do: index

  defp choose_clause!(_candidates, _no_match, context), do: refuse_undecided_branch!(context)

  # The clauses a branch may take, in order: every clause not ruled out up to the first one known to
  # match - the ones after it are never reached - or to the last clause.
  defp clause_candidates(clauses, outcome) do
    clauses
    |> Enum.with_index()
    |> Enum.reduce_while([], fn {clause, index}, candidates ->
      case outcome.(clause) do
        :match -> {:halt, [index | candidates]}
        :no_match -> {:cont, candidates}
        :unknown -> {:cont, [index | candidates]}
      end
    end)
    |> Enum.reverse()
  end

  # Whether a clause matches the given values, as Elixir decides it: every pattern matches its
  # value and a guard holds. A pattern on a value the build does not know, or a guard reading one,
  # leaves it unknown. A pattern the walk takes no bindings from is refused by the given binder.
  defp clause_outcome(patterns, guards, values, env, binder, context) do
    patterns_outcome =
      patterns
      |> Enum.zip(values)
      |> Enum.reduce_while({:match, %{}}, fn {pattern, value}, {outcome, bindings} ->
        with {pattern_outcome, new_bindings} <- pattern_outcome(pattern, value, binder),
             {bound_outcome, merged_bindings} <- bound_together(bindings, new_bindings) do
          combined_outcome =
            outcome
            |> weaker(pattern_outcome)
            |> weaker(bound_outcome)

          {:cont, {combined_outcome, merged_bindings}}
        else
          :no_match -> {:halt, :no_match}
        end
      end)

    case patterns_outcome do
      :no_match -> :no_match
      {outcome, bindings} -> guards_outcome(guards, Map.merge(env, bindings), outcome, context)
    end
  end

  # Every refusal here is raised while sweeping modules that are ALREADY COMPILED, so the BEAM
  # stacktrace names this module rather than the code the developer wrote. The location travels in
  # the exception instead - the file of the module being walked, and the line last reached in it.
  @spec compile_error!(String.t(), map) :: no_return
  defp compile_error!(message, context) do
    raise Hologram.CompileError,
      message: message,
      file: context_file(context),
      line: context.line,
      stack: context.stack
  end

  # A read the build performs for real, so a bad one is a bad builder - reported like every other
  # build refusal here, naming the derived field the ArgumentError-free raisers of Map cannot know
  # about.
  defp concrete_field!(value, field, context) when is_map(value) do
    case Map.fetch(value, field) do
      {:ok, field_value} ->
        field_value

      :error ->
        known =
          value
          |> Map.keys()
          |> Enum.sort()
          |> Enum.map_join(", ", &inspect/1)

        compile_error!(
          "#{context.subject} reads field #{inspect(field)} off a value that has no such field - known fields: #{known}",
          context
        )
    end
  end

  defp concrete_field!(value, field, context) do
    compile_error!(
      "#{context.subject} reads field #{inspect(field)} off #{inspect(value)}, which is not a map",
      context
    )
  end

  # The file a refusal is located in: the module being walked - or, in a derived field's own clause,
  # the file the field is declared in, which the clause is generated into.
  defp context_file(%{derived: %{at_field?: true, file: file}}), do: file

  defp context_file(context), do: source_file(context.current_module)

  # The clause of the entity type's __derived_definition__/1 the field's definition is built by.
  defp derived_clause!(entity_type, name, ir_plt) do
    {_fun_key, {_visibility, clauses}} =
      entity_type
      |> module_funs(ir_plt)
      |> List.keyfind({:__derived_definition__, 1}, 0)

    Enum.find(clauses, &match?(%IR.FunctionClause{params: [%IR.AtomType{value: ^name}]}, &1))
  end

  # Whether the walk stands in the derived field's own clause, where a builder is called from.
  defp derived_level?(context), do: context.derived.at_field?

  # A closure keeps only the variables its clause names, as an Elixir function captures them - so
  # what it holds tells whether it depends on the row (see stand_in?/1).
  defp evaluate!(%IR.AnonymousFunctionType{arity: arity, clauses: [clause]}, state, context) do
    closure_env = Map.take(state.env, ir_variables(clause))

    {anonymous_closure!(arity, clause, closure_env, context), state}
  end

  defp evaluate!(%IR.AnonymousFunctionType{}, _state, context) do
    compile_error!(
      "#{context.subject} uses a multi-clause anonymous function - not resolvable at build time yet",
      context
    )
  end

  defp evaluate!(%IR.AtomType{value: value}, state, _context), do: {value, state}

  defp evaluate!(%IR.Block{expressions: expressions}, state, context) do
    Enum.reduce(expressions, {nil, state}, fn expression, {_value, acc_state} ->
      evaluate!(expression, acc_state, context)
    end)
  end

  defp evaluate!(%IR.Case{condition: condition, clauses: clauses, line: line}, state, context) do
    context = with_line(context, line)

    {condition_value, state_after_condition} = evaluate!(condition, state, context)

    candidates =
      clause_candidates(clauses, fn clause ->
        clause_outcome(
          [clause.match],
          clause.guards,
          [condition_value],
          state_after_condition.env,
          &case_clause_env!(&1, condition_value, %{}, context),
          context
        )
      end)

    no_match =
      "#{context.subject} reaches a case on #{inspect(condition_value)}, which no clause matches - the code raises CaseClauseError there"

    clause = Enum.at(clauses, choose_clause!(candidates, no_match, context))

    clause_env =
      case_clause_env!(clause.match, condition_value, state_after_condition.env, context)

    {value, state_after_body} =
      evaluate!(clause.body, %{state_after_condition | env: clause_env}, context)

    {value, %{state_after_body | env: state_after_condition.env}}
  end

  defp evaluate!(%IR.Cond{clauses: clauses, line: line}, state, context) do
    context = with_line(context, line)

    evaluate_cond!(clauses, state, context)
  end

  defp evaluate!(%IR.DotOperator{left: left, right: right, line: line}, state, context) do
    context = with_line(context, line)

    {left_value, state_after_left} = evaluate!(left, state, context)
    {field, state_after_field} = evaluate!(right, state_after_left, context)

    case left_value do
      # A related row is read further through its relationships, as a derived field's body reads a
      # chain on an argument.
      %RowRef{owner: owner, path: path} ->
        {apply_derived!(:field, [owner, List.insert_at(path, -1, field)], context),
         state_after_field}

      %Query{source: {owner, chain}} = term ->
        {sourced_field!(term, owner, chain, field, context), state_after_field}

      %RowField{name: name} ->
        compile_error!(
          "#{context.subject} reads #{field} off the #{Stage.inspect_name(name)} field of the row, which holds a value - a path goes through relationships",
          context
        )

      value ->
        # A key that is a field of the row can be the one read, so the value depends on the row.
        if row_keyed?(value) do
          compile_error!(
            "#{context.subject} reads #{inspect(field)} off a map keyed by a field of the row - which value that is depends on the row",
            context
          )
        end

        {concrete_field!(value, field, context), state_after_field}
    end
  end

  defp evaluate!(%IR.FloatType{value: value}, state, _context), do: {value, state}

  defp evaluate!(%IR.IntegerType{value: value}, state, _context), do: {value, state}

  defp evaluate!(%IR.ListType{data: data}, state, context) do
    evaluate_enum!(data, state, context)
  end

  defp evaluate!(
         %IR.LocalFunctionCall{function: function, args: args, line: line},
         state,
         context
       ) do
    context = with_line(context, line)

    {arg_values, state_after_args} = evaluate_enum!(args, state, context)

    # In a derived field's own clause a local call is the entity type's own query builder, held to
    # what a builder of another module is.
    if derived_level?(context) do
      builder_call!(context.current_module, function, arg_values, state_after_args, context)
    else
      interpret_call!(context.current_module, function, arg_values, state_after_args, context)
    end
  end

  defp evaluate!(%IR.MapType{data: data}, state, context) do
    # Put in source order, so that of two keys that turn out equal the later one's value stays, as
    # in Elixir.
    Enum.reduce(data, {%{}, state}, fn {key_ir, value_ir}, {acc_map, acc_state} ->
      {key, state_after_key} = evaluate!(key_ir, acc_state, context)
      {value, state_after_value} = evaluate!(value_ir, state_after_key, context)

      {Map.put(acc_map, key, value), state_after_value}
    end)
  end

  defp evaluate!(
         %IR.MatchOperator{
           left: %IR.Variable{name: name, version: version},
           right: right,
           line: line
         },
         state,
         context
       ) do
    context = with_line(context, line)

    {value, new_state} = evaluate!(right, state, context)

    {value, %{new_state | env: Map.put(new_state.env, {name, version}, value)}}
  end

  defp evaluate!(
         %IR.MatchOperator{left: %IR.MatchPlaceholder{}, right: right, line: line},
         state,
         context
       ) do
    evaluate!(right, state, with_line(context, line))
  end

  defp evaluate!(%IR.MatchOperator{line: line}, _state, context) do
    context = with_line(context, line)

    compile_error!(
      "#{context.subject} pattern-matches in its body - only plain variable binds can be resolved at build time yet",
      context
    )
  end

  defp evaluate!(
         %IR.RemoteFunctionCall{module: module_ir, function: function, args: args, line: line},
         state,
         context
       ) do
    context = with_line(context, line)

    {target_module, state_after_module} = evaluate!(module_ir, state, context)
    {arg_values, state_after_args} = evaluate_enum!(args, state_after_module, context)

    if not is_atom(target_module) do
      compile_error!(
        "#{context.subject} calls #{function}/#{length(args)} on #{inspect(target_module)}, which is not a module",
        context
      )
    end

    cond do
      target_module in [Query, Stage] ->
        {apply_authored_stage!(function, arg_values, context), state_after_args}

      target_module == Derived ->
        {apply_derived!(function, arg_values, context), state_after_args}

      derived_level?(context) ->
        builder_call!(target_module, function, arg_values, state_after_args, context)

      stand_in?(arg_values) ->
        stand_in_call!(target_module, function, arg_values, state_after_args, context)

      # Every value given is one the build knows, so the call is run for real.
      true ->
        record_derived_read(target_module)

        {known_call!(target_module, function, arg_values, context), state_after_args}
    end
  end

  defp evaluate!(%IR.StringType{value: value}, state, _context), do: {value, state}

  defp evaluate!(%IR.TupleType{data: data}, state, context) do
    {values, new_state} = evaluate_enum!(data, state, context)

    {List.to_tuple(values), new_state}
  end

  # A variable is read by its name and version: the walk keeps every binding apart, so one the
  # compiler introduced - the x an if expands into - never hides the developer's own x.
  defp evaluate!(%IR.Variable{name: name, version: version}, state, _context) do
    {Map.fetch!(state.env, {name, version}), state}
  end

  defp evaluate!(ir, _state, context) do
    compile_error!(
      "#{context.subject} uses #{inspect(ir.__struct__)} - the construct is not resolvable at build time yet",
      context
    )
  end

  # A known condition decides its clause, as the cond does at runtime, and an unknown one is
  # refused. Past every clause the code raises.
  defp evaluate_cond!([], _state, context) do
    compile_error!(
      "#{context.subject} reaches a cond none of whose conditions holds - the code raises CondClauseError there",
      context
    )
  end

  defp evaluate_cond!([clause | rest], state, context) do
    {condition_value, state_after_condition} = evaluate!(clause.condition, state, context)

    cond do
      stand_in?(condition_value) ->
        refuse_undecided_branch!(context)

      condition_value in [nil, false] ->
        evaluate_cond!(rest, state_after_condition, context)

      true ->
        evaluate_cond_body!(clause, state_after_condition, context)
    end
  end

  defp evaluate_cond_body!(clause, state, context) do
    {value, state_after_body} = evaluate!(clause.body, state, context)

    {value, %{state_after_body | env: state.env}}
  end

  defp evaluate_enum!(irs, state, context) do
    {reversed_values, new_state} =
      Enum.reduce(irs, {[], state}, fn ir, {acc_values, acc_state} ->
        {value, next_state} = evaluate!(ir, acc_state, context)

        {[value | acc_values], next_state}
      end)

    {Enum.reverse(reversed_values), new_state}
  end

  defp fetch_function_clauses!(funs, module, function, arity, context) do
    case List.keyfind(funs, {function, arity}, 0) do
      {_fun_key, {_visibility, clauses}} ->
        clauses

      nil ->
        compile_error!(
          undefined_function_message(context.subject, module, function, arity),
          context
        )
    end
  end

  # An Elixir stacktrace entry, which is what a frame has to BE rather than resemble: it renders
  # through Exception.format_stacktrace_entry/1 and the live-reload overlay reads it by the same
  # shape it reads the compiler's own frames by.
  defp frame(module, function, arity, line) do
    {module, function, arity, [file: source_file(module), line: line]}
  end

  defp guard_call(module, function, args) do
    {:known, apply(module, function, args)}
  rescue
    _error -> :failed
  end

  # A guard's value over the bound values: {:known, value}, :unknown when it reads a value the build
  # does not know, or :failed when it raises. andalso and orelse are operators rather than functions,
  # so they are short-circuited here, and every other call in a guard is an Erlang one, run natively.
  defp guard_value(%IR.RemoteFunctionCall{function: operator, args: [left, right]}, env, context)
       when operator in [:andalso, :orelse] do
    case {operator, guard_value(left, env, context)} do
      {:andalso, {:known, false}} -> {:known, false}
      {:andalso, {:known, true}} -> guard_value(right, env, context)
      {:orelse, {:known, true}} -> {:known, true}
      {:orelse, {:known, false}} -> guard_value(right, env, context)
      {_operator, :unknown} -> :unknown
      {_operator, _failed_or_not_boolean} -> :failed
    end
  end

  defp guard_value(
         %IR.RemoteFunctionCall{
           module: %IR.AtomType{value: module},
           function: function,
           args: args
         },
         env,
         context
       ) do
    case guard_values(args, env, & &1, context) do
      {:known, arg_values} -> guard_call(module, function, arg_values)
      unknown_or_failed -> unknown_or_failed
    end
  end

  defp guard_value(%IR.DotOperator{left: left, right: right}, env, context) do
    case guard_values([left, right], env, & &1, context) do
      {:known, [map, key]} when is_map(map) ->
        if Map.has_key?(map, key), do: {:known, Map.fetch!(map, key)}, else: :failed

      {:known, _not_a_map} ->
        :failed

      unknown_or_failed ->
        unknown_or_failed
    end
  end

  defp guard_value(%IR.Variable{name: name, version: version}, env, _context) do
    case Map.fetch(env, {name, version}) do
      {:ok, value} -> if stand_in?(value), do: :unknown, else: {:known, value}
      :error -> :unknown
    end
  end

  defp guard_value(%IR.ListType{data: data}, env, context),
    do: guard_values(data, env, & &1, context)

  defp guard_value(%IR.MapType{data: data}, env, context) do
    data
    |> Enum.flat_map(fn {key, value} -> [key, value] end)
    |> guard_values(env, &map_of_pairs/1, context)
  end

  defp guard_value(%IR.TupleType{data: data}, env, context),
    do: guard_values(data, env, &List.to_tuple/1, context)

  defp guard_value(%{__struct__: struct, value: value}, _env, _context)
       when struct in [IR.AtomType, IR.FloatType, IR.IntegerType, IR.StringType],
       do: {:known, value}

  # A guard construct the walk does not evaluate would leave the clause undecided, and the walk has
  # to decide every branch, so the construct is refused for what it is.
  defp guard_value(ir, _env, context) do
    compile_error!(
      "#{context.subject} uses #{inspect(ir.__struct__)} in a guard - the construct is not resolvable at build time yet",
      context
    )
  end

  defp guard_values(irs, env, build, context) do
    values = Enum.map(irs, &guard_value(&1, env, context))

    cond do
      :failed in values ->
        :failed

      :unknown in values ->
        :unknown

      true ->
        built =
          values
          |> known_values()
          |> build.()

        {:known, built}
    end
  end

  # Whether any of a clause's guards holds - none means the clause is not guarded. A guard that
  # raises does not hold, as in Elixir.
  defp guards_outcome([], _env, outcome, _context), do: outcome

  defp guards_outcome(guards, env, outcome, context) do
    values = Enum.map(guards, &guard_value(&1, env, context))

    cond do
      {:known, true} in values -> outcome
      :unknown in values -> :unknown
      true -> :no_match
    end
  end

  defp interpret_anonymous!(clause, arg_values, closure_env, context) do
    # The head decides as a named function's does, with a guard free to read what the closure holds.
    candidates =
      clause_candidates([clause], fn clause ->
        clause_outcome(
          clause.params,
          clause.guards,
          arg_values,
          closure_env,
          &call_binding!(&1, nil, context),
          context
        )
      end)

    no_match =
      "#{context.subject} calls an anonymous function with #{Enum.map_join(arg_values, ", ", &inspect/1)}, which no clause matches - the code raises FunctionClauseError there"

    choose_clause!(candidates, no_match, context)

    call_env = call_env!(clause.params, arg_values, closure_env, context)

    # A closure runs when the function it was given to calls it, after the walk that built it moved
    # on, so its walk starts from a state of its own.
    state = %{env: call_env, funs_cache: %{}}

    {value, _state} = evaluate!(clause.body, state, context)

    # Only native code calls a closure, so a stand-in returned here would reach it unseen. One the
    # closure holds is refused before the call, and this is one it made itself.
    if stand_in?(value) do
      compile_error!(
        "#{context.subject} returns a field of the row from a function handed to another call - a field of the row reaches query stages and query builders only",
        context
      )
    end

    value
  end

  defp interpret_call!(module, function, arg_values, state, context) do
    arity = length(arg_values)
    mfa = {module, function, arity}

    # The MFA alone, never the whole frame: a frame carries the line the walk last reached inside
    # that function, so one helper called from two lines would otherwise read as two functions.
    if mfa in Enum.map(context.stack, fn {frame_module, frame_function, frame_arity, _location} ->
         {frame_module, frame_function, frame_arity}
       end) do
      compile_error!(
        "#{context.subject} recursively calls #{inspect(module)}.#{function}/#{arity} - recursive helpers can't be resolved at build time",
        context
      )
    end

    record_derived_read(module)

    {funs, state_after_funs} = module_funs_cached(module, state, context.ir_plt)

    clauses = fetch_function_clauses!(funs, module, function, arity, context)

    candidates =
      clause_candidates(clauses, fn clause ->
        clause_outcome(
          clause.params,
          clause.guards,
          arg_values,
          %{},
          &call_binding!(&1, nil, context),
          context
        )
      end)

    no_match = no_clause_message(context.subject, module, function, arg_values)

    clause = Enum.at(clauses, choose_clause!(candidates, no_match, context))
    call_env = call_env!(clause.params, arg_values, %{}, context)
    # The line starts unknown in the function being entered - the caller's line belongs to the
    # caller's frame, and pairing it with the callee's file would name a line in the wrong module.
    # A function the walk enters is no derived field's own clause, wherever it is defined.
    new_context = %{
      context
      | current_module: module,
        derived: %{context.derived | at_field?: false},
        line: nil,
        stack: [frame(module, function, arity, nil) | context.stack]
    }

    {value, state_after_body} =
      evaluate!(clause.body, %{state_after_funs | env: call_env}, new_context)

    {value, %{state_after_body | env: state_after_funs.env}}
  end

  # The variables an IR term names at any depth, nested functions included.
  defp ir_variables(%IR.Variable{name: name, version: version}), do: [{name, version}]

  defp ir_variables([head | tail]), do: ir_variables(head) ++ ir_variables(tail)

  defp ir_variables(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> ir_variables()
  end

  defp ir_variables(map) when is_map(map) do
    map
    |> Map.values()
    |> ir_variables()
  end

  defp ir_variables(_term), do: []

  # Only application-owned Elixir modules outside the Elixir-shipped apps are followed into - their
  # IR is what the build follows a field of the row through, and their edits are what can change a
  # definition. Classified through loaded application specs, never through Mix, which releases do
  # not ship.
  defp interpretable_module?(module) do
    case :application.get_application(module) do
      {:ok, app} -> app not in @elixir_apps and Reflection.elixir_module?(module)
      :undefined -> false
    end
  end

  # A call the build runs for real. Only the function it was asked to call is reported as missing:
  # one that exists and fails on a call of its own raises what it raises.
  defp known_call!(module, function, args, context) do
    apply(module, function, args)
  rescue
    error in UndefinedFunctionError ->
      if {error.module, error.function, error.arity} == {module, function, length(args)} do
        message =
          undefined_function_message(context.subject, module, function, length(args))

        compile_error!(message, context)
      else
        reraise error, __STACKTRACE__
      end
  end

  defp known_values(values), do: Enum.map(values, fn {:known, value} -> value end)

  defp map_of_pairs(flat_pairs) do
    flat_pairs
    |> Enum.chunk_every(2)
    |> Map.new(fn [key, value] -> {key, value} end)
  end

  # A module the PLT holds is read from it, one it lacks is built into it, so that the next read of
  # it, by this walk or another, finds it. Looked up before the build is asked for: building
  # nothing still lists the consolidated beams of the code path (see
  # Hologram.Compiler.build_ir_plt/1).
  defp module_funs(module, ir_plt) do
    ir =
      case PLT.get(ir_plt, module) do
        {:ok, ir} ->
          ir

        :error ->
          Compiler.build_missing_ir!(ir_plt, [module])
          PLT.get!(ir_plt, module)
      end

    IR.aggregate_module_funs(ir)
  end

  defp no_clause_message(subject, module, function, arg_values) do
    "#{subject} calls #{inspect(module)}.#{function}/#{length(arg_values)} with #{Enum.map_join(arg_values, ", ", &inspect/1)}, which no clause matches - the code raises FunctionClauseError there"
  end

  # Whether a clause head's pattern matches a value: always for a name or _, by the literal's equality
  # for a literal - unknown when the build does not know the value - with the bindings it makes.
  defp pattern_outcome(%IR.Variable{name: name, version: version}, value, _binder),
    do: {:match, %{{name, version} => value}}

  defp pattern_outcome(%IR.MatchPlaceholder{}, _value, _binder), do: {:match, %{}}

  defp pattern_outcome(%{__struct__: struct, value: literal}, value, _binder)
       when struct in [IR.AtomType, IR.FloatType, IR.IntegerType, IR.StringType] do
    cond do
      stand_in?(value) -> {:unknown, %{}}
      value === literal -> {:match, %{}}
      true -> :no_match
    end
  end

  defp pattern_outcome(pattern, _value, binder), do: binder.(pattern)

  defp module_funs_cached(module, state, ir_plt) do
    case state.funs_cache do
      %{^module => funs} ->
        {funs, state}

      _missing ->
        funs = module_funs(module, ir_plt)

        {funs, %{state | funs_cache: Map.put(state.funs_cache, module, funs)}}
    end
  end

  # A project module whose function a derived field's walk follows or runs is one whose edit can
  # change the definition - Elixir's own modules never change between compiles of an app.
  defp record_derived_read(module) do
    if interpretable_module?(module) do
      Process.put(@derived_reads_key, MapSet.put(Process.get(@derived_reads_key), module))
    end

    :ok
  end

  # A derived field's definition is built once, before any row is read, so a branch the build cannot
  # decide is one on a field of the row - the one value a derived field's walk does not know.
  @spec refuse_undecided_branch!(map) :: no_return
  defp refuse_undecided_branch!(context) do
    compile_error!(
      "#{context.subject} branches on a field of the row - a derived field's definition is one query, built before any row is read",
      context
    )
  end

  # A module compiled in memory - a fixture defined inside a test file, or anything built at run
  # time - records "nofile" as its source, which locates nothing. The name arrives absolutized
  # against the working directory, so it is the basename that identifies it.
  defp source_file(module) do
    path = Reflection.source_path(module)

    if Path.basename(path) == "nofile", do: nil, else: path
  end

  # A closure can run in a process of a call the build runs, where the walk's key is unset.
  defp row_expressions, do: Process.get(@row_expressions_key, MapSet.new())

  defp row_keyed?(map) when is_map(map) do
    map
    |> Map.keys()
    |> Enum.any?(&row_value?/1)
  end

  defp row_keyed?(_value), do: false

  defp row_value?(%RowField{}), do: true

  defp row_value?(%RowRef{}), do: true

  defp row_value?(%Query{source: source}), do: source != nil

  defp row_value?(value), do: MapSet.member?(row_expressions(), value)

  # A dot on a set reads further through its rows, as a derived field's body reads a chain through a
  # set - only before a stage narrowed it, since the longer path is a set of its own.
  defp sourced_field!(term, owner, chain, field, context) do
    if term != Stage.sourced(owner, chain) do
      compile_error!(
        "#{context.subject} reads #{field} off a set its stages narrowed - a path goes through relationships, before any stage reads the set",
        context
      )
    end

    apply_derived!(:field, [owner, List.insert_at(chain, -1, field)], context)
  end

  # Whether a value holds a stand-in for a field of the row a derived field is computed for - the
  # one kind of value the walk does not know.
  defp stand_in?(%RowField{}), do: true

  defp stand_in?(%RowRef{}), do: true

  defp stand_in?(%Query{source: source}), do: source != nil

  # Walked cell by cell, since a value the build computed can be an improper list.
  defp stand_in?([head | tail]), do: stand_in?(head) or stand_in?(tail)

  # A function depends on the row when it holds a stand-in, called or only compared.
  defp stand_in?(function) when is_function(function) do
    {:env, env} = Function.info(function, :env)

    stand_in?(env)
  end

  defp stand_in?(tuple) when is_tuple(tuple) do
    row_value?(tuple) or
      tuple
      |> Tuple.to_list()
      |> stand_in?()
  end

  defp stand_in?(map) when is_map(map) do
    map
    |> Map.to_list()
    |> stand_in?()
  end

  defp stand_in?(_value), do: false

  # Inside a query builder a stand-in goes where a query goes: into another builder of the project,
  # followed into its IR.
  defp stand_in_call!(module, function, arg_values, state, context) do
    if not interpretable_module?(module) do
      compile_error!(
        "#{context.subject} passes a field of the row to #{inspect(module)}.#{function}/#{length(arg_values)} - a field of the row reaches query stages and query builders only",
        context
      )
    end

    interpret_call!(module, function, arg_values, state, context)
  end

  # A node carrying no line leaves the last one standing rather than blanking it - metadata is
  # missing here and there, and the nearest enclosing line still locates the refusal.
  defp with_line(context, nil), do: context

  # The field's own clause is generated, so its nodes carry lines of the generating code - the
  # declaration's line stands for every one of them.
  defp with_line(%{derived: %{at_field?: true}} = context, _line), do: context

  defp with_line(context, line) do
    %{context | line: line, stack: relocated_stack(context.stack, line)}
  end

  # The head frame is the function the walk is inside, so its line moves with the walk - that is
  # what makes a caller's frame name the line it called FROM rather than the line it started at.
  # There is always one: the derived field's own frame opens the stack before its body is walked.
  defp relocated_stack([{module, function, arity, _location} | rest_frames], line) do
    [frame(module, function, arity, line) | rest_frames]
  end

  defp undefined_function_message(subject, module, function, arity) do
    "#{subject} calls undefined function #{inspect(module)}.#{function}/#{arity}"
  end

  defp weaker(:match, outcome), do: outcome

  defp weaker(:unknown, _outcome), do: :unknown
end
