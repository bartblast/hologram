defmodule Hologram.Compiler.QueryExtractor do
  @moduledoc false

  alias Hologram.Compiler.IR
  alias Hologram.Query
  alias Hologram.Query.Placeholder
  alias Hologram.Reflection

  # The applications shipped with Elixir itself - their modules are never
  # interpreted, so a placeholder reaching them raises the flow error naming the
  # call the developer wrote instead of its internals.
  @elixir_apps [:eex, :elixir, :ex_unit, :iex, :logger, :mix]

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
  symbolically over its IR - each argument becomes a placeholder flowing into
  the term as a `{:placeholder, name}` leaf named after the argument, resolving through
  the generated from_query shim when the capture points at one. Branching forks
  the evaluation: every case/cond clause, every capture head clause, and every
  clause of a multi-clause helper yields its own variant term, all variants are
  extracted (deduplicated per capture), and clause guards are never evaluated -
  a variant that cannot occur at runtime is over-approximation, costing a
  registry entry, never correctness. A literal head pattern fixes its argument
  concretely in that variant.

  Calls interpret transitively: local helpers and placeholder-receiving functions
  compiled into the project build evaluate over their own IR (recursion is
  rejected), placeholder-free remote calls and query stage calls run natively, and
  single-clause anonymous functions evaluate on invocation with their captured
  scope (branch-free bodies only).

  ANYTHING THE BUILD CAN EVALUATE IS PART OF THE QUERY, ANYTHING IT CANNOT IS A
  PLACEHOLDER. That is the whole rule, and what it serves is the sync window - which
  rows a client downloads - never validation, which happens when the query runs
  against real values on either tier. A call the build cannot make yields a
  placeholder named for the argument it derives from.

  Where a placeholder may land follows from the window, not from the term. A
  position `Hologram.Query.Window` drops or empties takes one as a leaf: a filter
  attribute or value, an ordering key or direction, a view bound. A position the
  window is DERIVED from cannot - the entity says which table to download, an
  include name says which relationship travels with it - so those FORK instead,
  one variant per candidate of a finite set (every entity type of the build, or the
  target's declared relationships). A candidate the query itself refuses is pruned,
  which is what narrows the set: `filter(entity.type, done: false)` keeps precisely
  the types declaring a boolean `done`. Everything a pruned candidate caused is
  pruned with it, however deep, so a sub-builder refusing a speculated relationship
  kills that variant rather than the build.

  Raises Hologram.CompileError when a from_query value is not a function capture,
  when a capture argument is destructured instead of a plain name, when a capture
  argument is named vars (reserved), when a case clause or function head uses a
  composite pattern, when a helper recurses, when an anonymous function has
  multiple clauses, arity above 3, or branches, when a body uses a construct
  symbolic evaluation does not cover, when a placeholder stands somewhere the build
  can neither drop nor enumerate (a whole predicates list, a paginate option map, a
  sub-builder), or when no candidate survives - a prop with no window would read
  rows nothing ever fills. Zero-arity captures are free of these limits - they
  evaluate concretely at build time.

  The entity types are the fork's candidate set for a placeholder in an entity
  position. They are taken as an argument so that a build computes them once and
  passes the one list to every extraction, rather than every fork reading them -
  the default sweeps the build's apps, for one-off calls.
  """
  @spec extract_module_queries(module, list(module)) :: list(%{atom => any})
  def extract_module_queries(module, entity_types \\ Reflection.list_entities()) do
    if Reflection.has_function?(module, :__props__, 0) do
      Enum.flat_map(module.__props__(), &prop_queries!(module, &1, entity_types))
    else
      []
    end
  end

  @doc """
  Extracts the ordered argument names of every parameterized from_query capture
  on the given module's prop declarations. Names merge positionally across the
  capture target's clauses (resolving through the generated from_query shim when
  the capture points at one) - a position no clause binds as a plain variable
  yields nil. Zero-arity captures and modules without prop declarations yield no
  entries.

  One position takes ONE name across every clause. The name is what says which
  prop feeds the argument, and the value is chosen before clause dispatch happens,
  so two clauses naming a position differently pose a question nothing can answer.
  Clauses that do not use a position leave it a literal or an underscored name and
  cost nothing.

  Raises Hologram.CompileError when a position carries more than one distinct
  name.

  The names are read from compiled beams rather than recorded by the prop macro
  into the prop's own opts, because a remote capture's names are unreadable while
  the consuming component compiles: a target module compiling in the same batch
  exists only in memory, and its beam - the only carrier of its clauses - is
  written when the batch ends.
  """
  @spec extract_prop_params(module) :: keyword(list(atom | nil))
  def extract_prop_params(module) do
    if Reflection.has_function?(module, :__props__, 0) do
      Enum.flat_map(module.__props__(), &prop_params(module, &1))
    else
      []
    end
  end

  @doc """
  Extracts the registered query terms declared by the given modules - the
  concatenated extract_module_queries/2 results in module order.
  """
  @spec extract_queries(list(module), list(module)) :: list(%{atom => any})
  def extract_queries(modules, entity_types \\ Reflection.list_entities()) do
    Enum.flat_map(modules, &extract_module_queries(&1, entity_types))
  end

  @doc """
  Validates that every parameterized from_query capture on the given module's prop
  declarations binds only the module's declared reactive slots - today, the props it
  is given, which is every declared prop except the ones from_query itself fills. A
  builder's argument names bind the like-named slots of the consuming component, so a
  shared builder is validated against each consumer's own slots.

  Raises Hologram.CompileError when a capture argument names no declared slot, when it
  names a from_query prop of the same component, or when an argument position is named
  by no clause of the capture's target. Modules without parameterized captures pass
  vacuously.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/query_extractor/validate_slot_bindings!_1/README.md
  """
  @spec validate_slot_bindings!(module) :: :ok
  def validate_slot_bindings!(module) do
    case extract_prop_params(module) do
      [] ->
        :ok

      prop_params ->
        names = %{queries: query_prop_names(module), slots: declared_slot_names(module)}

        Enum.each(prop_params, fn {prop_name, param_names} ->
          Enum.each(param_names, &validate_slot_binding!(module, prop_name, &1, names))
        end)
    end
  end

  # A closure evaluates with choices :none - a fork inside would restart the
  # whole body with a stale choice list, so branching inside raises instead.
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
      "query capture for prop #{inspect(context.prop_name)} in #{inspect(context.prop_module)} uses an anonymous function of arity #{arity} - only arities 1-3 are extractable yet",
      context
    )
  end

  # The query position decides WHICH TABLE the window downloads, so unlike a value it cannot stay a
  # placeholder. The candidates are finite - every entity type of the build - so the evaluation
  # FORKS over them, exactly as it forks a case clause, and each variant becomes its own window.
  #
  # What narrows the set is the query itself: a variant the stage refuses (an attribute that type
  # does not declare, an operand of the wrong type) is PRUNED, so `filter(entity.type, done: false)`
  # keeps precisely the types declaring a boolean `done`. No separate narrowing rule exists, and
  # none should - Hologram.Query's own validation is the satisfiability check.
  # One position per pass, recursing until none is left - a query whose entity AND include name both
  # arrive at run time forks twice, over the product of the two candidate sets.
  defp apply_query_stage!(function, arg_values, state, context) do
    case forked_position(function, arg_values, context) do
      nil ->
        {apply_authored_stage!(function, arg_values, context), state}

      {index, candidates} ->
        {choice, state_after_choice} = take_choice!(state, length(candidates), context)

        substituted_args = List.replace_at(arg_values, index, Enum.at(candidates, choice))

        apply_speculated_stage!(function, substituted_args, state_after_choice, context)
    end
  end

  # The two positions a placeholder cannot stay in, because the window is derived from them: the
  # entity says which table to download, an include name says which relationship travels with it.
  # Both have a finite candidate set, so both fork rather than refuse.
  #
  # An entity declaring no relationship yields no candidates, so there is nothing to fork over and
  # the call falls through to the stage, which refuses the placeholder - located when the developer
  # named that entity, pruned when a fork chose it.
  #
  # The entity set arrives in the context, computed once by whoever drives the build - the fork
  # re-enters the body once per candidate, so anything computed at this point would run once per
  # variant, and listing the build's entity types sweeps every app's ebin directory.
  defp forked_position(_function, [%Placeholder{} | _rest_args], context) do
    {0, context.entity_types}
  end

  defp forked_position(:include, [query | [%Placeholder{} | _rest_args]], _context) do
    case relationship_names(query) do
      [] -> nil
      names -> {1, names}
    end
  end

  defp forked_position(_function, _arg_values, _context), do: nil

  defp relationship_names(%{entity: entity_type}), do: relationship_names(entity_type)

  defp relationship_names(entity_type) when is_atom(entity_type) do
    Enum.map(entity_type.__relationships__(), fn {name, _target, _opts} -> name end)
  end

  # A stage call the developer wrote is theirs to read, so a refusal from it is reraised carrying
  # the prop it belongs to, which the ArgumentError cannot know.
  defp apply_authored_stage!(function, arg_values, context) do
    apply(Query, function, arg_values)
  rescue
    error in ArgumentError ->
      reraise Hologram.CompileError,
              [
                message: stage_error_message(function, arg_values, error, context),
                file: source_file(context.current_module),
                line: context.line
              ],
              __STACKTRACE__
  end

  # A stage the BUILD speculated, never the developer. Its refusal says the candidate is wrong, not
  # that the query is - so the variant dies and the others carry on.
  #
  # The rescue wraps the whole substituted call, so EVERYTHING a candidate makes happen is
  # speculative however deep it runs: a sub-builder refusing the relationship the fork chose is the
  # fork's problem, not the developer's. A builder with no fork in it never reaches here, which is
  # what keeps an authored mistake loud - apply_authored_stage!/3 reraises it with the prop's name.
  # A fork signal is a throw rather than an exception, so it passes through untouched.
  defp apply_speculated_stage!(function, arg_values, state, context) do
    apply_query_stage!(function, arg_values, state, context)
  rescue
    ArgumentError -> throw(@prune_signal)
    Hologram.CompileError -> throw(@prune_signal)
  end

  # A cover-compiled module (coverage runs) is loaded from instrumented code,
  # but its beam still lives on disk in the code path.
  defp beam_path(module) do
    case :code.which(module) do
      :cover_compiled ->
        case :code.get_object_code(module) do
          {^module, _binary, path} -> path
          :error -> :error
        end

      other ->
        other
    end
  end

  defp call_binding!(%IR.Variable{name: name}, value, _context), do: {name, value}

  defp call_binding!(%IR.AtomType{}, _value, _context), do: nil

  defp call_binding!(%IR.FloatType{}, _value, _context), do: nil

  defp call_binding!(%IR.IntegerType{}, _value, _context), do: nil

  defp call_binding!(%IR.MatchPlaceholder{}, _value, _context), do: nil

  defp call_binding!(%IR.StringType{}, _value, _context), do: nil

  defp call_binding!(_param_ir, _value, context) do
    compile_error!(
      "query capture for prop #{inspect(context.prop_name)} in #{inspect(context.prop_module)} calls a function whose head destructures a parameter - only plain names, literals, and _ are extractable yet",
      context
    )
  end

  defp call_env!(placeholders, arg_values, base_env, context) do
    placeholders
    |> Enum.zip(arg_values)
    |> Enum.reduce(base_env, fn {param_ir, value}, env ->
      case call_binding!(param_ir, value, context) do
        {name, bound_value} -> Map.put(env, name, bound_value)
        nil -> env
      end
    end)
  end

  defp case_clause_env!(%IR.Variable{name: name}, condition_value, env, _context) do
    Map.put(env, name, condition_value)
  end

  defp case_clause_env!(%IR.AtomType{}, _condition_value, env, _context), do: env

  defp case_clause_env!(%IR.FloatType{}, _condition_value, env, _context), do: env

  defp case_clause_env!(%IR.IntegerType{}, _condition_value, env, _context), do: env

  defp case_clause_env!(%IR.MatchPlaceholder{}, _condition_value, env, _context), do: env

  defp case_clause_env!(%IR.StringType{}, _condition_value, env, _context), do: env

  defp case_clause_env!(_pattern_ir, _condition_value, _env, context) do
    compile_error!(
      "query capture for prop #{inspect(context.prop_name)} in #{inspect(context.prop_module)} uses a composite case pattern - only variables, literals, and _ are extractable yet",
      context
    )
  end

  # Every refusal here is raised while sweeping modules that are ALREADY COMPILED, so the BEAM
  # stacktrace names this module rather than the code the developer wrote. The location travels in
  # the exception instead - the file of the module being walked, and the line last reached in it.
  @spec compile_error!(String.t(), map) :: no_return
  defp compile_error!(message, context) do
    compile_error!(message, context.current_module, context.line)
  end

  defp compile_error!(message, module, line) do
    raise Hologram.CompileError,
      message: message,
      file: source_file(module),
      line: line
  end

  # A read the build performs for real, so a bad one is a bad builder - reported like every other
  # build refusal here, naming the prop the ArgumentError-free raisers of Map cannot know about.
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
          "query capture for prop #{inspect(context.prop_name)} in #{inspect(context.prop_module)} reads field #{inspect(field)} off a value that has no such field - known fields: #{known}",
          context
        )
    end
  end

  defp concrete_field!(value, field, context) do
    compile_error!(
      "query capture for prop #{inspect(context.prop_name)} in #{inspect(context.prop_module)} reads field #{inspect(field)} off #{inspect(value)}, which is not a map",
      context
    )
  end

  defp contains_placeholder?(%Placeholder{}), do: true

  defp contains_placeholder?(list) when is_list(list) do
    Enum.any?(list, &contains_placeholder?/1)
  end

  defp contains_placeholder?(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.any?(&contains_placeholder?/1)
  end

  defp contains_placeholder?(map) when is_map(map) do
    map
    |> Map.to_list()
    |> Enum.any?(&contains_placeholder?/1)
  end

  defp contains_placeholder?(_other), do: false

  # The set a builder argument may bind - the component's declared reactive slots, which today
  # means the props it is GIVEN and nothing else. Declared state and derived values extend this
  # set later without reshaping the check.
  #
  # A prop that from_query fills is not one of them: it is what a query PRODUCED, not something
  # the component was handed. Binding one would make a query's answer depend on another query's,
  # which nothing here orders - the injector runs them in declaration order, so the same two
  # declarations resolve or raise depending on which was written first.
  defp declared_slot_names(module) do
    module.__props__()
    |> Enum.reject(fn {_name, _type, opts} -> opts[:from_query] end)
    |> Enum.map(fn {name, _type, _opts} -> name end)
  end

  defp query_prop_names(module) do
    module.__props__()
    |> Enum.filter(fn {_name, _type, opts} -> opts[:from_query] end)
    |> Enum.map(fn {name, _type, _opts} -> name end)
  end

  defp evaluate!(%IR.AnonymousFunctionType{arity: arity, clauses: [clause]}, state, context) do
    {anonymous_closure!(arity, clause, state.env, context), state}
  end

  defp evaluate!(%IR.AnonymousFunctionType{}, _state, context) do
    compile_error!(
      "query capture for prop #{inspect(context.prop_name)} in #{inspect(context.prop_module)} uses a multi-clause anonymous function - not extractable yet",
      context
    )
  end

  defp evaluate!(%IR.AtomType{value: value}, state, _context), do: {value, state}

  defp evaluate!(%IR.Block{expressions: expressions}, state, context) do
    Enum.reduce(expressions, {nil, state}, fn expression, {_value, acc_state} ->
      evaluate!(expression, acc_state, context)
    end)
  end

  # Clause guards are deliberately never evaluated at a fork - every clause
  # forks a variant regardless of satisfiability (over-approximation).
  defp evaluate!(%IR.Case{condition: condition, clauses: clauses, line: line}, state, context) do
    context = with_line(context, line)

    {condition_value, state_after_condition} = evaluate!(condition, state, context)

    {choice, state_after_choice} =
      take_choice!(state_after_condition, length(clauses), context)

    clause = Enum.at(clauses, choice)
    clause_env = case_clause_env!(clause.match, condition_value, state_after_choice.env, context)

    {value, state_after_body} =
      evaluate!(clause.body, %{state_after_choice | env: clause_env}, context)

    {value, %{state_after_body | env: state_after_choice.env}}
  end

  defp evaluate!(%IR.Cond{clauses: clauses, line: line}, state, context) do
    context = with_line(context, line)

    evaluate_cond!(clauses, state, context)
  end

  # Reading a field off a placeholder yields another placeholder, named for the path read.
  #
  # Nothing executes the extracted term - both tiers call the real builder with the component's real
  # prop values - so the leaf only has to say that the value is unknown until the query runs.
  # sobelow_skip ["DOS.BinToAtom"]
  defp evaluate!(%IR.DotOperator{left: left, right: right, line: line}, state, context) do
    context = with_line(context, line)

    {left_value, state_after_left} = evaluate!(left, state, context)
    {field, state_after_field} = evaluate!(right, state_after_left, context)

    case left_value do
      # The name is built from source-level field names, so the set is bounded by the code itself.
      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      %Placeholder{name: name} -> {%Placeholder{name: :"#{name}.#{field}"}, state_after_field}
      value -> {concrete_field!(value, field, context), state_after_field}
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

    interpret_call!(context.current_module, function, arg_values, state_after_args, context)
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

  defp evaluate!(
         %IR.MatchOperator{left: %IR.Variable{name: name}, right: right, line: line},
         state,
         context
       ) do
    context = with_line(context, line)

    {value, new_state} = evaluate!(right, state, context)

    {value, %{new_state | env: Map.put(new_state.env, name, value)}}
  end

  defp evaluate!(%IR.MatchOperator{}, _state, context) do
    compile_error!(
      "query capture for prop #{inspect(context.prop_name)} in #{inspect(context.prop_module)} pattern-matches in its body - only plain variable binds are extractable yet",
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

    cond do
      target_module == Query ->
        apply_query_stage!(function, arg_values, state_after_args, context)

      not contains_placeholder?(arg_values) ->
        {apply(target_module, function, arg_values), state_after_args}

      interpretable_module?(target_module) ->
        interpret_call!(target_module, function, arg_values, state_after_args, context)

      true ->
        {%Placeholder{name: first_placeholder_name(arg_values)}, state_after_args}
    end
  end

  defp evaluate!(%IR.StringType{value: value}, state, _context), do: {value, state}

  defp evaluate!(%IR.TupleType{data: data}, state, context) do
    {values, new_state} = evaluate_enum!(data, state, context)

    {List.to_tuple(values), new_state}
  end

  defp evaluate!(%IR.Variable{name: name}, state, _context) do
    {Map.fetch!(state.env, name), state}
  end

  defp evaluate!(ir, _state, context) do
    compile_error!(
      "query capture for prop #{inspect(context.prop_name)} in #{inspect(context.prop_module)} uses #{inspect(ir.__struct__)} - the construct is not extractable yet",
      context
    )
  end

  defp evaluate_cond!([], _state, _context) do
    throw(@prune_signal)
  end

  defp evaluate_cond!([clause | rest], state, context) do
    {_condition_value, state_after_condition} = evaluate!(clause.condition, state, context)

    {choice, state_after_choice} = take_choice!(state_after_condition, 2, context)

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
        {term, _state} =
          evaluate!(body, %{choices: choices, env: env, funs_cache: %{}}, context)

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

  defp fetch_function_clauses!(funs, module, function, arity, context) do
    case List.keyfind(funs, {function, arity}, 0) do
      {_fun_key, {_visibility, clauses}} ->
        clauses

      nil ->
        compile_error!(
          "query capture for prop #{inspect(context.prop_name)} in #{inspect(context.prop_module)} calls undefined function #{inspect(module)}.#{function}/#{arity}",
          context
        )
    end
  end

  # A computed value carries the name of the argument it derives from - the first one reached, and
  # any of them says the same thing about the term: this is not knowable until the query runs. The
  # name never reaches a window id (Hologram.Query.Window drops what a placeholder stands in), so what it
  # is FOR is saying which argument the value came from when a term is read.
  defp first_placeholder_name(%Placeholder{name: name}), do: name

  defp first_placeholder_name(list) when is_list(list) do
    Enum.find_value(list, &first_placeholder_name/1)
  end

  defp first_placeholder_name(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> first_placeholder_name()
  end

  defp first_placeholder_name(map) when is_map(map) do
    map
    |> Map.to_list()
    |> first_placeholder_name()
  end

  defp first_placeholder_name(_other), do: nil

  # TODO: an argument named vars will bind the full assigns bag once that
  # convention lands - until then the name is reserved.
  defp head_binding!(module, prop_name, %IR.Variable{name: :vars}, line) do
    compile_error!(
      "query capture for prop #{inspect(prop_name)} in #{inspect(module)} names an argument vars - the name is reserved, name arguments after the component assigns they bind to",
      module,
      line
    )
  end

  defp head_binding!(_module, _prop_name, %IR.Variable{name: name}, _line) do
    {name, %Placeholder{name: name}}
  end

  defp head_binding!(_module, _prop_name, %IR.AtomType{}, _line), do: nil

  defp head_binding!(_module, _prop_name, %IR.FloatType{}, _line), do: nil

  defp head_binding!(_module, _prop_name, %IR.IntegerType{}, _line), do: nil

  defp head_binding!(_module, _prop_name, %IR.MatchPlaceholder{}, _line), do: nil

  defp head_binding!(_module, _prop_name, %IR.StringType{}, _line), do: nil

  defp head_binding!(module, prop_name, _param_ir, line) do
    compile_error!(
      "query capture for prop #{inspect(prop_name)} in #{inspect(module)} destructures an argument - arguments must be plain names, each binding to the like-named component assign",
      module,
      line
    )
  end

  defp head_env!(module, prop_name, clause) do
    Enum.reduce(clause.params, %{}, fn param_ir, env ->
      case head_binding!(module, prop_name, param_ir, clause.line) do
        {name, value} -> Map.put(env, name, value)
        nil -> env
      end
    end)
  end

  defp interpret_anonymous!(clause, arg_values, closure_env, context) do
    call_env = call_env!(clause.params, arg_values, closure_env, context)

    state = %{choices: :none, env: call_env, funs_cache: %{}}

    {value, _state} = evaluate!(clause.body, state, context)

    value
  end

  defp interpret_call!(module, function, arg_values, state, context) do
    arity = length(arg_values)
    frame = {module, function, arity}

    if frame in context.stack do
      compile_error!(
        "query capture for prop #{inspect(context.prop_name)} in #{inspect(context.prop_module)} recursively calls #{inspect(module)}.#{function}/#{arity} - recursive helpers are not extractable",
        context
      )
    end

    {funs, state_after_funs} = module_funs_cached(module, state)

    clauses = fetch_function_clauses!(funs, module, function, arity, context)

    {choice, state_after_choice} =
      case clauses do
        [_single_clause] -> {0, state_after_funs}
        _multiple_clauses -> take_choice!(state_after_funs, length(clauses), context)
      end

    clause = Enum.at(clauses, choice)
    call_env = call_env!(clause.params, arg_values, %{}, context)
    new_context = %{context | current_module: module, stack: [frame | context.stack]}

    {value, state_after_body} =
      evaluate!(clause.body, %{state_after_choice | env: call_env}, new_context)

    {value, %{state_after_body | env: state_after_choice.env}}
  end

  # Only application-owned Elixir modules outside the Elixir-shipped apps are interpreted - their IR
  # is what the build has to follow a placeholder through. A call this refuses is not an error: the
  # build cannot compute it, so its result becomes a placeholder like any other unknown value.
  # Classified through loaded application specs, never through Mix, which releases do not ship.
  defp interpretable_module?(module) do
    case :application.get_application(module) do
      {:ok, app} -> app not in @elixir_apps and Reflection.elixir_module?(module)
      :undefined -> false
    end
  end

  # A position named by some clauses and left a literal by others merges to the one name - that is
  # what this is for, and it is how a `def q(nil)` clause sits beside a `def q(min_b)` one. Two
  # clauses naming it DIFFERENTLY is the shape that cannot merge, since the caller must pick a
  # prop's value before any clause is chosen.
  defp merged_placeholder_names(module, prop_name, clauses, arity) do
    Enum.map(0..(arity - 1), fn index ->
      clauses
      |> Enum.map(&param_name(&1, index))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> merged_param_name!(module, prop_name, index, hd(clauses).line)
    end)
  end

  defp merged_param_name!([], _module, _prop_name, _index, _line), do: nil

  defp merged_param_name!([name], _module, _prop_name, _index, _line), do: name

  defp merged_param_name!(names, module, prop_name, index, line) do
    spelled = Enum.map_join(names, ", ", &inspect/1)

    compile_error!(
      "query capture for prop #{inspect(prop_name)} in #{inspect(module)} names argument #{index + 1} differently across its clauses (#{spelled}) - one argument position binds one prop, and which prop it is has to be known before any clause is chosen, so every clause must name it alike. Rename them to the prop this argument binds, leave the position a literal or an underscored name in the clauses that do not use it, or bind through an adapter naming it once: from_query: fn #{hd(names)} -> your_query(#{hd(names)}) end",
      module,
      line
    )
  end

  defp module_funs(module) do
    beam_source =
      case beam_path(module) do
        path when is_list(path) -> path
        _other -> nil
      end

    module
    |> IR.for_module(beam_source)
    |> IR.aggregate_module_funs()
  end

  defp param_name(clause, index) do
    case Enum.at(clause.params, index) do
      %IR.Variable{name: name} -> name
      _pattern -> nil
    end
  end

  defp prop_params(module, {name, _type, opts}) do
    with {:ok, capture} <- Keyword.fetch(opts, :from_query),
         true <- is_function(capture) and not is_function(capture, 0) do
      {_target_module, clauses} = resolve_capture_clauses!(module, name, capture)
      arity = Function.info(capture)[:arity]

      [{name, merged_placeholder_names(module, name, clauses, arity)}]
    else
      _absent_zero_arity_or_non_capture -> []
    end
  end

  defp module_funs_cached(module, state) do
    case state.funs_cache do
      %{^module => funs} ->
        {funs, state}

      _missing ->
        funs = module_funs(module)

        {funs, %{state | funs_cache: Map.put(state.funs_cache, module, funs)}}
    end
  end

  defp prop_queries!(module, {name, _type, opts}, entity_types) do
    case Keyword.fetch(opts, :from_query) do
      {:ok, capture} -> prop_query!(module, name, capture, entity_types)
      :error -> []
    end
  end

  defp prop_query!(_module, _prop_name, capture, _entity_types) when is_function(capture, 0) do
    [Query.normalize(capture.())]
  end

  defp prop_query!(module, prop_name, capture, entity_types) when is_function(capture) do
    {target_module, clauses} = resolve_capture_clauses!(module, prop_name, capture)

    context = %{
      current_module: target_module,
      entity_types: entity_types,
      line: nil,
      prop_module: module,
      prop_name: prop_name,
      stack: []
    }

    terms =
      clauses
      |> Enum.flat_map(fn clause ->
        env = head_env!(module, prop_name, clause)

        evaluate_variants!(clause.body, env, context, [])
      end)
      |> Enum.map(&Query.normalize/1)
      |> Enum.uniq()

    if terms == [] do
      compile_error!(
        "query capture for prop #{inspect(prop_name)} in #{inspect(module)} builds no query that any entity type of the build admits - a prop with no window would read rows nothing ever fills",
        target_module,
        hd(clauses).line
      )
    end

    terms
  end

  defp prop_query!(module, prop_name, value, _entity_types) do
    compile_error!(
      "from_query for prop #{inspect(prop_name)} in #{inspect(module)} must be a function capture, got: #{inspect(value)}",
      module,
      nil
    )
  end

  defp resolve_capture_clauses!(prop_module, prop_name, capture) do
    capture_info = Function.info(capture)
    target_module = capture_info[:module]

    fun_name = shim_target(target_module, capture_info[:name])
    arity = capture_info[:arity]

    funs = module_funs(target_module)

    case List.keyfind(funs, {fun_name, arity}, 0) do
      {_fun_key, {_visibility, clauses}} ->
        {target_module, clauses}

      nil ->
        compile_error!(
          "query capture for prop #{inspect(prop_name)} in #{inspect(prop_module)} targets undefined function #{inspect(target_module)}.#{fun_name}/#{arity}",
          prop_module,
          nil
        )
    end
  end

  # A generated delegation shim hides the authored builder - the component's
  # delegations reflection maps it back. An inline-hoisted shim is the authored
  # builder itself and is not listed there.
  defp shim_target(module, fun_name) do
    if function_exported?(module, :__from_query_delegations__, 0) do
      Keyword.get(module.__from_query_delegations__(), fun_name, fun_name)
    else
      fun_name
    end
  end

  # An argument among the values gets a message of its own. The value it stands for arrives long
  # after the build, so what went wrong is that a query's SHAPE was asked to depend on it - and
  # naming the placeholder would show a compiler internal to someone who wrote a prop.
  # A module compiled in memory - a fixture defined inside a test file, or anything built at run
  # time - records "nofile" as its source, which locates nothing. The name arrives absolutized
  # against the working directory, so it is the basename that identifies it.
  defp source_file(module) do
    path = Reflection.source_path(module)

    if Path.basename(path) == "nofile", do: nil, else: path
  end

  defp stage_error_message(function, arg_values, error, context) do
    prefix =
      "query capture for prop #{inspect(context.prop_name)} in #{inspect(context.prop_module)}"

    if contains_placeholder?(arg_values) do
      "#{prefix} passes an argument to #{function}/#{length(arg_values)} in a position the build cannot enumerate - the rows to download cannot be worked out without its value"
    else
      "#{prefix} builds an invalid query - #{Exception.message(error)}"
    end
  end

  # A node carrying no line leaves the last one standing rather than blanking it - metadata is
  # missing here and there, and the nearest enclosing line still locates the refusal.
  defp with_line(context, nil), do: context

  defp with_line(context, line), do: %{context | line: line}

  defp take_choice!(%{choices: [choice | rest]} = state, _clause_count, _context) do
    {choice, %{state | choices: rest}}
  end

  defp take_choice!(%{choices: []}, clause_count, _context) do
    throw({@fork_signal, clause_count})
  end

  defp take_choice!(%{choices: :none}, _clause_count, context) do
    compile_error!(
      "query capture for prop #{inspect(context.prop_name)} in #{inspect(context.prop_module)} branches inside an anonymous function - not extractable yet",
      context
    )
  end

  defp validate_slot_binding!(module, prop_name, nil, _slot_names) do
    compile_error!(
      "from_query capture for prop #{inspect(prop_name)} in #{inspect(module)} has an argument position no clause names - it cannot bind a prop",
      module,
      nil
    )
  end

  defp validate_slot_binding!(module, prop_name, placeholder_name, names) do
    cond do
      placeholder_name in names.slots ->
        :ok

      placeholder_name in names.queries ->
        compile_error!(
          "from_query for prop #{inspect(prop_name)} in #{inspect(module)} binds argument #{inspect(placeholder_name)}, which is a from_query prop of the same component - a query argument binds a value the component is GIVEN, never one another query produced",
          module,
          nil
        )

      true ->
        compile_error!(
          "from_query for prop #{inspect(prop_name)} in #{inspect(module)} binds argument #{inspect(placeholder_name)} - no like-named prop is declared",
          module,
          nil
        )
    end
  end
end
