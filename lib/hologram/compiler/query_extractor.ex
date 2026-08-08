defmodule Hologram.Compiler.QueryExtractor do
  @moduledoc false

  alias Hologram.Compiler.IR
  alias Hologram.Query
  alias Hologram.Query.Param

  @doc """
  Extracts the registered query terms declared by the given module - the normalized
  terms of every `from_query:` capture on the module's prop declarations.

  A zero-arity capture is invoked at build time (query builders are pure term
  constructors) and its result normalized. A capture with arguments is evaluated
  symbolically over its IR - each argument becomes a param sentinel flowing into
  the term as a `{:param, name}` leaf named after the argument, resolving through
  the generated from_query shim when the capture points at one. Symbolic
  evaluation supports straight-line bodies: literals, data construction, variable
  binds, and function calls - calls run natively, and sentinels may only flow
  into query stage calls. Modules without prop declarations declare no queries.

  Raises Hologram.CompileError when a from_query value is not a function capture,
  when a capture argument is destructured instead of a plain name, when a capture
  argument is named vars (reserved), when a parameterized capture branches -
  multiple clauses, a guarded clause, or a branching construct in its body - or
  when its body calls a local function, passes a sentinel to a non-stage call, or
  uses a construct symbolic evaluation does not cover. Zero-arity captures are
  free of these limits - they evaluate concretely at build time.
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

  defp contains_branching?(%IR.AnonymousFunctionType{clauses: [_clause_1, _clause_2 | _rest]}) do
    true
  end

  defp contains_branching?(%IR.Case{}), do: true

  defp contains_branching?(%IR.Cond{}), do: true

  defp contains_branching?(%IR.Try{}), do: true

  defp contains_branching?(%IR.With{}), do: true

  defp contains_branching?(ir) when is_struct(ir) do
    ir
    |> Map.from_struct()
    |> Map.values()
    |> Enum.any?(&contains_branching?/1)
  end

  defp contains_branching?(list) when is_list(list) do
    Enum.any?(list, &contains_branching?/1)
  end

  defp contains_branching?(_other), do: false

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

  defp evaluate!(%IR.AtomType{value: value}, env, _context), do: {value, env}

  defp evaluate!(%IR.Block{expressions: expressions}, env, context) do
    Enum.reduce(expressions, {nil, env}, fn expression, {_value, acc_env} ->
      evaluate!(expression, acc_env, context)
    end)
  end

  defp evaluate!(%IR.FloatType{value: value}, env, _context), do: {value, env}

  defp evaluate!(%IR.IntegerType{value: value}, env, _context), do: {value, env}

  defp evaluate!(%IR.ListType{data: data}, env, context) do
    evaluate_enum!(data, env, context)
  end

  # TODO: transitive interpretation evaluates helper bodies - until then, helper
  # calls in parameterized builders fail the build.
  defp evaluate!(%IR.LocalFunctionCall{function: function, args: args}, _env, context) do
    {module, prop_name} = context

    raise Hologram.CompileError,
      message:
        "query capture for prop #{inspect(prop_name)} in #{inspect(module)} calls local function #{function}/#{length(args)} - helper composition is not extractable yet"
  end

  defp evaluate!(%IR.MapType{data: data}, env, context) do
    {pairs, new_env} =
      Enum.reduce(data, {[], env}, fn {key_ir, value_ir}, {acc_pairs, acc_env} ->
        {key, env_after_key} = evaluate!(key_ir, acc_env, context)
        {value, env_after_value} = evaluate!(value_ir, env_after_key, context)

        {[{key, value} | acc_pairs], env_after_value}
      end)

    {Map.new(pairs), new_env}
  end

  defp evaluate!(%IR.MatchOperator{left: %IR.Variable{name: name}, right: right}, env, context) do
    {value, new_env} = evaluate!(right, env, context)

    {value, Map.put(new_env, name, value)}
  end

  defp evaluate!(%IR.MatchOperator{}, _env, context) do
    {module, prop_name} = context

    raise Hologram.CompileError,
      message:
        "query capture for prop #{inspect(prop_name)} in #{inspect(module)} pattern-matches in its body - only plain variable binds are extractable yet"
  end

  defp evaluate!(
         %IR.RemoteFunctionCall{module: module_ir, function: function, args: args},
         env,
         context
       ) do
    {target_module, env_after_module} = evaluate!(module_ir, env, context)
    {arg_values, new_env} = evaluate_enum!(args, env_after_module, context)

    validate_symbol_flow!(target_module, function, arg_values, context)

    {apply(target_module, function, arg_values), new_env}
  end

  defp evaluate!(%IR.StringType{value: value}, env, _context), do: {value, env}

  defp evaluate!(%IR.TupleType{data: data}, env, context) do
    {values, new_env} = evaluate_enum!(data, env, context)

    {List.to_tuple(values), new_env}
  end

  defp evaluate!(%IR.Variable{name: name}, env, _context) do
    {Map.fetch!(env, name), env}
  end

  defp evaluate!(ir, _env, {module, prop_name}) do
    raise Hologram.CompileError,
      message:
        "query capture for prop #{inspect(prop_name)} in #{inspect(module)} uses #{inspect(ir.__struct__)} - the construct is not extractable yet"
  end

  defp evaluate_enum!(irs, env, context) do
    {reversed_values, new_env} =
      Enum.reduce(irs, {[], env}, fn ir, {acc_values, acc_env} ->
        {value, next_env} = evaluate!(ir, acc_env, context)

        {[value | acc_values], next_env}
      end)

    {Enum.reverse(reversed_values), new_env}
  end

  defp module_funs(module) do
    module
    |> IR.for_module()
    |> IR.aggregate_module_funs()
  end

  # TODO: an argument named vars will bind the full assigns bag once that
  # convention lands - until then the name is reserved.
  defp param_name!(module, prop_name, %IR.Variable{name: :vars}) do
    raise Hologram.CompileError,
      message:
        "query capture for prop #{inspect(prop_name)} in #{inspect(module)} names an argument vars - the name is reserved, name arguments after the component assigns they bind to"
  end

  defp param_name!(_module, _prop_name, %IR.Variable{name: name}), do: name

  defp param_name!(module, prop_name, _param_ir) do
    raise Hologram.CompileError,
      message:
        "query capture for prop #{inspect(prop_name)} in #{inspect(module)} destructures an argument - arguments must be plain names, each binding to the like-named component assign"
  end

  defp prop_queries!(module, {name, _type, opts}) do
    case Keyword.fetch(opts, :from_query) do
      {:ok, capture} -> [prop_query!(module, name, capture)]
      :error -> []
    end
  end

  defp prop_query!(_module, _prop_name, capture) when is_function(capture, 0) do
    Query.normalize(capture.())
  end

  defp prop_query!(module, prop_name, capture) when is_function(capture) do
    {clause, param_names} = resolve_capture_clause!(module, prop_name, capture)

    env = Map.new(param_names, &{&1, %Param{name: &1}})

    {term, _env} = evaluate!(clause.body, env, {module, prop_name})

    Query.normalize(term)
  end

  defp prop_query!(module, prop_name, value) do
    raise Hologram.CompileError,
      message:
        "from_query for prop #{inspect(prop_name)} in #{inspect(module)} must be a function capture, got: #{inspect(value)}"
  end

  defp resolve_capture_clause!(module, prop_name, capture) do
    capture_info = Function.info(capture)
    funs = module_funs(capture_info[:module])

    fun_name = shim_target(funs, module, prop_name, capture_info)
    fun_key = {fun_name, capture_info[:arity]}

    {^fun_key, {_visibility, clauses}} = List.keyfind(funs, fun_key, 0)

    clause = validate_straight_line!(module, prop_name, clauses)

    param_names = Enum.map(clause.params, &param_name!(module, prop_name, &1))

    {clause, param_names}
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

  # TODO: branch forking over the IR registers every variant of a branching
  # builder - until then, branching parameterized builders fail the build.
  defp validate_straight_line!(module, prop_name, [_clause_1, _clause_2 | _rest]) do
    raise Hologram.CompileError,
      message:
        "query capture for prop #{inspect(prop_name)} in #{inspect(module)} has multiple clauses - branching parameterized builders are not extractable yet"
  end

  defp validate_straight_line!(module, prop_name, [%IR.FunctionClause{guards: guards}])
       when guards != [] do
    raise Hologram.CompileError,
      message:
        "query capture for prop #{inspect(prop_name)} in #{inspect(module)} has a guarded clause - branching parameterized builders are not extractable yet"
  end

  defp validate_straight_line!(module, prop_name, [clause]) do
    if contains_branching?(clause.body) do
      raise Hologram.CompileError,
        message:
          "query capture for prop #{inspect(prop_name)} in #{inspect(module)} branches in its body - branching parameterized builders are not extractable yet"
    end

    clause
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
