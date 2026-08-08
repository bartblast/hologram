defmodule Hologram.Compiler.QueryExtractor do
  @moduledoc false

  alias Hologram.Compiler.IR
  alias Hologram.Query
  alias Hologram.Query.Param

  # Fork enumeration uses throw for non-local exit: on an undecided branch the
  # evaluation aborts, and the driver restarts it from the body with one more
  # branch choice appended (depth-first over the choice tree).
  @fork_signal :hologram_query_extractor_fork
  @prune_signal :hologram_query_extractor_prune

  @doc """
  Extracts the registered query terms declared by the given module - the normalized
  terms of every `from_query:` capture on the module's prop declarations.

  A zero-arity capture is invoked at build time (query builders are pure term
  constructors) and its result normalized. A capture with arguments is evaluated
  symbolically over its IR - each argument becomes a param sentinel flowing into
  the term as a `{:param, name}` leaf named after the argument, resolving through
  the generated from_query shim when the capture points at one. Branching forks
  the evaluation: every case/cond clause and every capture head clause yields
  its own variant term, all variants are extracted (deduplicated per capture),
  and clause guards are never evaluated - a variant that cannot occur at runtime
  is over-approximation, costing a registry entry, never correctness. A literal
  head pattern fixes its argument concretely in that variant. Straight-line
  evaluation covers literals, data construction, variable binds, and function
  calls - calls run natively, and sentinels may only flow into query stage
  calls. Modules without prop declarations declare no queries.

  Raises Hologram.CompileError when a from_query value is not a function capture,
  when a capture argument is destructured instead of a plain name, when a capture
  argument is named vars (reserved), when a case clause uses a composite pattern,
  or when a body calls a local function, passes a sentinel to a non-stage call,
  or uses a construct symbolic evaluation does not cover. Zero-arity captures
  are free of these limits - they evaluate concretely at build time.
  """
  @spec extract_module_queries(module) :: list(%{atom => any})
  def extract_module_queries(module) do
    if function_exported?(module, :__props__, 0) do
      Enum.flat_map(module.__props__(), &prop_queries!(module, &1))
    else
      []
    end
  end

  @doc """
  Extracts the registered query terms declared by the given modules - the
  concatenated extract_module_queries/1 results in module order.
  """
  @spec extract_queries(list(module)) :: list(%{atom => any})
  def extract_queries(modules) do
    Enum.flat_map(modules, &extract_module_queries/1)
  end

  defp case_clause_env!(%IR.Variable{name: name}, condition_value, env, _context) do
    Map.put(env, name, condition_value)
  end

  defp case_clause_env!(%IR.AtomType{}, _condition_value, env, _context), do: env

  defp case_clause_env!(%IR.FloatType{}, _condition_value, env, _context), do: env

  defp case_clause_env!(%IR.IntegerType{}, _condition_value, env, _context), do: env

  defp case_clause_env!(%IR.MatchPlaceholder{}, _condition_value, env, _context), do: env

  defp case_clause_env!(%IR.StringType{}, _condition_value, env, _context), do: env

  defp case_clause_env!(_pattern_ir, _condition_value, _env, {module, prop_name}) do
    raise Hologram.CompileError,
      message:
        "query capture for prop #{inspect(prop_name)} in #{inspect(module)} uses a composite case pattern - only variables, literals, and _ are extractable yet"
  end

  defp contains_symbol?(%Param{}), do: true

  defp contains_symbol?(list) when is_list(list) do
    Enum.any?(list, &contains_symbol?/1)
  end

  defp contains_symbol?(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.any?(&contains_symbol?/1)
  end

  defp contains_symbol?(map) when is_map(map) do
    map
    |> Map.to_list()
    |> Enum.any?(&contains_symbol?/1)
  end

  defp contains_symbol?(_other), do: false

  defp evaluate!(%IR.AtomType{value: value}, state, _context), do: {value, state}

  defp evaluate!(%IR.Block{expressions: expressions}, state, context) do
    Enum.reduce(expressions, {nil, state}, fn expression, {_value, acc_state} ->
      evaluate!(expression, acc_state, context)
    end)
  end

  # Clause guards are deliberately never evaluated at a fork - every clause
  # forks a variant regardless of satisfiability (over-approximation).
  defp evaluate!(%IR.Case{condition: condition, clauses: clauses}, state, context) do
    {condition_value, state_after_condition} = evaluate!(condition, state, context)

    {choice, state_after_choice} = take_choice!(state_after_condition, length(clauses))

    clause = Enum.at(clauses, choice)
    clause_env = case_clause_env!(clause.match, condition_value, state_after_choice.env, context)

    {value, state_after_body} =
      evaluate!(clause.body, %{state_after_choice | env: clause_env}, context)

    {value, %{state_after_body | env: state_after_choice.env}}
  end

  defp evaluate!(%IR.Cond{clauses: clauses}, state, context) do
    evaluate_cond!(clauses, state, context)
  end

  defp evaluate!(%IR.FloatType{value: value}, state, _context), do: {value, state}

  defp evaluate!(%IR.IntegerType{value: value}, state, _context), do: {value, state}

  defp evaluate!(%IR.ListType{data: data}, state, context) do
    evaluate_enum!(data, state, context)
  end

  # TODO: transitive interpretation evaluates helper bodies - until then, helper
  # calls in parameterized builders fail the build.
  defp evaluate!(%IR.LocalFunctionCall{function: function, args: args}, _env, context) do
    {module, prop_name} = context

    raise Hologram.CompileError,
      message:
        "query capture for prop #{inspect(prop_name)} in #{inspect(module)} calls local function #{function}/#{length(args)} - helper composition is not extractable yet"
  end

  defp evaluate!(%IR.MapType{data: data}, state, context) do
    {pairs, new_state} =
      Enum.reduce(data, {[], state}, fn {key_ir, value_ir}, {acc_pairs, acc_state} ->
        {key, state_after_key} = evaluate!(key_ir, acc_state, context)
        {value, state_after_value} = evaluate!(value_ir, state_after_key, context)

        {[{key, value} | acc_pairs], state_after_value}
      end)

    {Map.new(pairs), new_state}
  end

  defp evaluate!(%IR.MatchOperator{left: %IR.Variable{name: name}, right: right}, state, context) do
    {value, new_state} = evaluate!(right, state, context)

    {value, %{new_state | env: Map.put(new_state.env, name, value)}}
  end

  defp evaluate!(%IR.MatchOperator{}, _env, context) do
    {module, prop_name} = context

    raise Hologram.CompileError,
      message:
        "query capture for prop #{inspect(prop_name)} in #{inspect(module)} pattern-matches in its body - only plain variable binds are extractable yet"
  end

  defp evaluate!(
         %IR.RemoteFunctionCall{module: module_ir, function: function, args: args},
         state,
         context
       ) do
    {target_module, state_after_module} = evaluate!(module_ir, state, context)
    {arg_values, new_state} = evaluate_enum!(args, state_after_module, context)

    validate_symbol_flow!(target_module, function, arg_values, context)

    {apply(target_module, function, arg_values), new_state}
  end

  defp evaluate!(%IR.StringType{value: value}, state, _context), do: {value, state}

  defp evaluate!(%IR.TupleType{data: data}, state, context) do
    {values, new_state} = evaluate_enum!(data, state, context)

    {List.to_tuple(values), new_state}
  end

  defp evaluate!(%IR.Variable{name: name}, state, _context) do
    {Map.fetch!(state.env, name), state}
  end

  defp evaluate!(ir, _state, {module, prop_name}) do
    raise Hologram.CompileError,
      message:
        "query capture for prop #{inspect(prop_name)} in #{inspect(module)} uses #{inspect(ir.__struct__)} - the construct is not extractable yet"
  end

  defp evaluate_cond!([], _state, _context) do
    throw(@prune_signal)
  end

  defp evaluate_cond!([clause | rest], state, context) do
    {_condition_value, state_after_condition} = evaluate!(clause.condition, state, context)

    {choice, state_after_choice} = take_choice!(state_after_condition, 2)

    if choice == 0 do
      {value, state_after_body} = evaluate!(clause.body, state_after_choice, context)

      {value, %{state_after_body | env: state_after_choice.env}}
    else
      evaluate_cond!(rest, state_after_choice, context)
    end
  end

  defp evaluate_enum!(irs, state, context) do
    {reversed_values, new_state} =
      Enum.reduce(irs, {[], state}, fn ir, {acc_values, acc_state} ->
        {value, next_state} = evaluate!(ir, acc_state, context)

        {[value | acc_values], next_state}
      end)

    {Enum.reverse(reversed_values), new_state}
  end

  defp evaluate_variants!(body, env, context, choices) do
    result =
      try do
        {term, _state} = evaluate!(body, %{choices: choices, env: env}, context)

        {:term, term}
      catch
        {@fork_signal, clause_count} -> {:fork, clause_count}
        @prune_signal -> :prune
      end

    case result do
      {:term, term} ->
        [term]

      :prune ->
        []

      {:fork, clause_count} ->
        Enum.flat_map(0..(clause_count - 1), fn choice ->
          evaluate_variants!(body, env, context, List.insert_at(choices, -1, choice))
        end)
    end
  end

  # TODO: an argument named vars will bind the full assigns bag once that
  # convention lands - until then the name is reserved.
  defp head_binding!(module, prop_name, %IR.Variable{name: :vars}) do
    raise Hologram.CompileError,
      message:
        "query capture for prop #{inspect(prop_name)} in #{inspect(module)} names an argument vars - the name is reserved, name arguments after the component assigns they bind to"
  end

  defp head_binding!(_module, _prop_name, %IR.Variable{name: name}) do
    {name, %Param{name: name}}
  end

  defp head_binding!(_module, _prop_name, %IR.AtomType{}), do: nil

  defp head_binding!(_module, _prop_name, %IR.FloatType{}), do: nil

  defp head_binding!(_module, _prop_name, %IR.IntegerType{}), do: nil

  defp head_binding!(_module, _prop_name, %IR.MatchPlaceholder{}), do: nil

  defp head_binding!(_module, _prop_name, %IR.StringType{}), do: nil

  defp head_binding!(module, prop_name, _param_ir) do
    raise Hologram.CompileError,
      message:
        "query capture for prop #{inspect(prop_name)} in #{inspect(module)} destructures an argument - arguments must be plain names, each binding to the like-named component assign"
  end

  defp head_env!(module, prop_name, clause) do
    Enum.reduce(clause.params, %{}, fn param_ir, env ->
      case head_binding!(module, prop_name, param_ir) do
        {name, value} -> Map.put(env, name, value)
        nil -> env
      end
    end)
  end

  defp module_funs(module) do
    module
    |> IR.for_module()
    |> IR.aggregate_module_funs()
  end

  defp prop_queries!(module, {name, _type, opts}) do
    case Keyword.fetch(opts, :from_query) do
      {:ok, capture} -> prop_query!(module, name, capture)
      :error -> []
    end
  end

  defp prop_query!(_module, _prop_name, capture) when is_function(capture, 0) do
    [Query.normalize(capture.())]
  end

  defp prop_query!(module, prop_name, capture) when is_function(capture) do
    context = {module, prop_name}

    module
    |> resolve_capture_clauses!(prop_name, capture)
    |> Enum.flat_map(fn clause ->
      env = head_env!(module, prop_name, clause)

      evaluate_variants!(clause.body, env, context, [])
    end)
    |> Enum.map(&Query.normalize/1)
    |> Enum.uniq()
  end

  defp prop_query!(module, prop_name, value) do
    raise Hologram.CompileError,
      message:
        "from_query for prop #{inspect(prop_name)} in #{inspect(module)} must be a function capture, got: #{inspect(value)}"
  end

  defp resolve_capture_clauses!(module, prop_name, capture) do
    capture_info = Function.info(capture)
    funs = module_funs(capture_info[:module])

    fun_name = shim_target(funs, module, prop_name, capture_info)
    fun_key = {fun_name, capture_info[:arity]}

    {^fun_key, {_visibility, clauses}} = List.keyfind(funs, fun_key, 0)

    clauses
  end

  defp shim_target(funs, module, prop_name, capture_info) do
    fun_name = capture_info[:name]

    shim? =
      capture_info[:module] == module and
        Atom.to_string(fun_name) == "__#{prop_name}_from_query__"

    if shim? do
      fun_key = {fun_name, capture_info[:arity]}

      {^fun_key, {_visibility, [shim_clause]}} = List.keyfind(funs, fun_key, 0)

      %IR.Block{expressions: [%IR.LocalFunctionCall{function: target_name}]} = shim_clause.body

      target_name
    else
      fun_name
    end
  end

  defp take_choice!(%{choices: [choice | rest]} = state, _clause_count) do
    {choice, %{state | choices: rest}}
  end

  defp take_choice!(%{choices: []}, clause_count) do
    throw({@fork_signal, clause_count})
  end

  # TODO: transitive interpretation lets sentinels flow into interpreted helper
  # bodies - until then, sentinels may only reach query stage calls.
  defp validate_symbol_flow!(Query, _function, _arg_values, _context), do: :ok

  defp validate_symbol_flow!(target_module, function, arg_values, {module, prop_name}) do
    if contains_symbol?(arg_values) do
      raise Hologram.CompileError,
        message:
          "query capture for prop #{inspect(prop_name)} in #{inspect(module)} passes an argument to #{inspect(target_module)}.#{function}/#{length(arg_values)} - arguments must flow directly into query stage calls, computing on them is not extractable yet"
    end

    :ok
  end
end
