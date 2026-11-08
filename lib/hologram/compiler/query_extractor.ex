defmodule Hologram.Compiler.QueryExtractor do
  @moduledoc false

  alias Hologram.Commons.PLT
  alias Hologram.Compiler
  alias Hologram.Compiler.IR
  alias Hologram.Entity
  alias Hologram.Entity.Derived
  alias Hologram.Entity.Derived.RowRef
  alias Hologram.MisuseError
  alias Hologram.Query
  alias Hologram.Query.Placeholder
  alias Hologram.Query.RowField
  alias Hologram.Query.Stage
  alias Hologram.Reflection

  # The applications shipped with Elixir itself - their modules are never
  # interpreted, so a placeholder reaching them raises the flow error naming the
  # call the developer wrote instead of its internals.
  @elixir_apps [:eex, :elixir, :ex_unit, :iex, :logger, :mix]

  # The modules a derived field's walk followed calls into or ran functions of, gathered across the
  # closures it runs, which start from states of their own.
  @derived_reads_key {__MODULE__, :derived_reads}

  # Fork enumeration uses throw for non-local exit: on an undecided branch the
  # evaluation aborts, and the driver restarts it from the body with one more
  # branch choice appended (depth-first over the choice tree).
  @fork_signal :hologram_query_extractor_fork
  @prune_signal :hologram_query_extractor_prune

  defmodule SymbolicQuery do
    @moduledoc false

    # A query the build cannot execute yet, because a position the WINDOW is derived from - the
    # entity that says which table to download, an include name that says which relationship
    # travels with it - is an argument. Nothing is built while the capture is walked: each stage
    # asked of it is recorded, and the record is replayed through Hologram.Query.Stage once the
    # candidates are known. So the developer's code runs once, and only the recorded stages -
    # a short list of data - are replayed per candidate.
    #
    # `base` is what the stages apply to: a placeholder, standing for every entity type of the
    # build, or a concrete entity type or query term when only an include name is unknown. Stages
    # are held newest-first and reversed at replay, each carrying the line it was written on - a
    # record that admits nothing is refused after the walk, where only the stages still say where.
    defstruct [:base, stages: []]

    @type t :: %__MODULE__{base: struct | module | map, stages: list({atom, list, integer | nil})}
  end

  @doc """
  Resolves the definition of the given derived field of the given entity type by walking the
  field's clause of the type's `__derived_definition__/1` over its IR - the way a body calling a
  query builder of another module is resolved, since the builder is written for the values it will
  be given, and a field of the row has none while the definition is built.

  What the walk reads stands in for the row's fields as `Hologram.Entity.Derived.field/2` builds
  them - a query over a set, a row field, a related row - and goes where a query goes: query stages
  and `Hologram.Entity.Derived` run natively over them, a call into another module of the project is
  followed into its IR with them, and a dot on a related row reads the longer path. The result is
  normalized as `Hologram.Entity.Derived.resolve/2` normalizes it, and returned with the modules
  whose functions the walk followed - the ones whose edits can change it besides the entity types'.
  A branch on a value the build knows takes the clause that value takes, as an extraction's does.

  Raises Hologram.CompileError, located where the walk stood, when a branch depends on a field of
  the row, when a field of the row reaches anything but a query stage, `Hologram.Entity.Derived` or
  a query builder, when a builder the body calls returns no query term, when a known value matches
  no clause, and on what an extraction refuses.
  """
  @spec derived_definition(module, atom, PLT.t()) :: {Derived.definition(), list(module)}
  def derived_definition(entity_type, name, ir_plt) do
    {file, line} = Map.fetch!(entity_type.__derived_locations__(), name)

    context = %{
      current_module: entity_type,
      derived: %{at_field?: true, file: file},
      entity_types: [],
      ir_plt: ir_plt,
      line: line,
      stack: [{entity_type, :__derived_definition__, 1, [file: file, line: line]}],
      subject: "derived field #{inspect(name)} in #{inspect(entity_type)}"
    }

    clause = derived_clause!(entity_type, name, ir_plt)

    Process.put(@derived_reads_key, MapSet.new())

    try do
      # Every branch of a derived field's walk is decided or refused, so the walk builds one
      # definition.
      [definition] = evaluate_variants!(clause.body, %{}, context, [], false)

      read_modules =
        @derived_reads_key
        |> Process.get()
        |> Enum.sort()

      {Derived.normalize(definition), read_modules}
    after
      Process.delete(@derived_reads_key)
    end
  end

  @doc """
  Extracts the registered query terms declared by the given module - the normalized
  terms of every `from_query:` capture on the module's prop declarations.

  A zero-arity capture is invoked at build time (query builders are pure term
  constructors) and its result normalized. A capture with arguments is evaluated
  symbolically over its IR - each argument becomes a placeholder flowing into
  the term as a `{:placeholder, name}` leaf named after the argument, resolving through
  the generated from_query shim when the capture points at one. A branch on a
  value the build knows - a case, a cond, a call to a multi-clause helper - takes
  the clause that value takes, its patterns and guards read in order as Elixir
  reads them, and a known value no clause matches is refused where the code would
  raise. A branch on an argument forks the evaluation: every clause the value could
  take yields its own variant term, as does every capture head clause, and all
  variants are extracted (deduplicated per capture) - a variant that cannot occur
  at runtime is over-approximation, costing a registry entry, never correctness. A
  literal head pattern fixes its argument concretely in that variant.

  Calls interpret transitively: local helpers and placeholder-receiving functions
  compiled into the project build evaluate over their own IR (recursion is
  rejected), placeholder-free remote calls and query stage calls run natively, and
  single-clause anonymous functions evaluate on invocation with their captured
  scope (a branch inside one only on a value the build knows).

  ANYTHING THE BUILD CAN EVALUATE IS PART OF THE QUERY, ANYTHING IT CANNOT IS A
  PLACEHOLDER. That is the whole rule, and what it serves is the sync window - which
  rows a client downloads - never validation, which happens when the query runs
  against real values on either tier. A call the build cannot make yields a
  placeholder named for the argument it derives from.

  Where a placeholder may land follows from the window, not from the term. A
  position `Hologram.Query.Window` drops or empties takes one as a leaf: a filter
  attribute or value, an ordering key or direction, a view bound. A position the
  window is DERIVED from cannot - the entity says which table to download, an
  include name says which relationship travels with it - so a query holding one is
  not built while the capture is walked at all: the stages asked of it are RECORDED,
  and the record is replayed through the builder once per candidate of a finite set
  (every entity type of the build, or the query's entity's declared relationships),
  keeping the variants the builder admits. The developer's code is walked once, and
  only the recorded stages are replayed. What narrows the set is the builder's own
  validation, whatever stage refuses: `filter(entity.type, done: false)` keeps
  precisely the types declaring a boolean `done`, and a candidate a LATER stage
  cannot satisfy - an entity declaring no relationship to include - is dropped rather
  than failing the build.

  Raises Hologram.CompileError when a from_query value is not a function capture,
  when a capture argument is destructured instead of a plain name, when a capture
  argument is named vars (reserved), when a case clause or function head uses a
  composite pattern, when a known value matches no clause, when a helper recurses,
  when an anonymous function has multiple clauses, arity above 3, or a branch on
  an argument, when a body uses a construct
  symbolic evaluation does not cover, when a placeholder stands somewhere the build
  can neither drop nor enumerate (a whole predicates list, a paginate option map), or
  when no candidate survives - a prop with no window would read
  rows nothing ever fills. Zero-arity captures are free of these limits - they
  evaluate concretely at build time.

  The entity types are the replay's candidate set for a placeholder in an entity
  position. They are taken as an argument so that a build computes them once and
  passes the one list to every extraction, rather than every extraction reading
  them.

  The IR a capture is walked over is read from the given IR PLT, the compile's: a
  module the PLT lacks is built into it (see Hologram.Compiler.build_missing_ir!/2),
  so that no module's IR is built twice in a compile.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/query_extractor/extract_module_queries_3/README.md
  """
  @spec extract_module_queries(module, list(module), PLT.t()) :: list(Query.t())
  def extract_module_queries(module, entity_types, ir_plt) do
    if Reflection.has_function?(module, :__props__, 0) do
      Enum.flat_map(module.__props__(), &prop_queries!(module, &1, entity_types, ir_plt))
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
  written when the batch ends. The beam is read through its IR, from the given IR
  PLT, as extract_module_queries/3 reads it.
  """
  @spec extract_prop_params(module, PLT.t()) :: keyword(list(atom | nil))
  def extract_prop_params(module, ir_plt) do
    if Reflection.has_function?(module, :__props__, 0) do
      Enum.flat_map(module.__props__(), &prop_params(module, &1, ir_plt))
    else
      []
    end
  end

  @doc """
  Extracts the registered query terms declared by the given modules - the
  concatenated extract_module_queries/3 results in module order.
  """
  @spec extract_queries(list(module), list(module), PLT.t()) :: list(Query.t())
  def extract_queries(modules, entity_types, ir_plt) do
    Enum.flat_map(modules, &extract_module_queries(&1, entity_types, ir_plt))
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

  The argument names are the ones extract_prop_params/2 extracted from the module, so
  that the check reads no IR of its own.
  """
  @spec validate_slot_bindings!(module, keyword(list(atom | nil))) :: :ok
  def validate_slot_bindings!(module, prop_params) do
    case prop_params do
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
  # whole body with a stale choice list, so a branch inside it on an argument raises instead.
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
      "#{context.subject} uses an anonymous function of arity #{arity} - only arities 1-3 are extractable yet",
      context
    )
  end

  # The query position decides WHICH TABLE the window downloads, so unlike a value it cannot stay a
  # placeholder. Rather than choosing a candidate here and re-walking the developer's code once per
  # choice, the stage is RECORDED against the placeholder and replayed later over a finite set -
  # every entity type of the build - each surviving replay becoming its own window.
  #
  # What narrows the set is the query itself: a candidate the builder refuses (an attribute that
  # type does not declare, an operand of the wrong type) is dropped at replay, so
  # `filter(entity.type, done: false)` keeps precisely the types declaring a boolean `done`. No
  # separate narrowing rule exists, and none should - Hologram.Query.Stage's own validation is the
  # satisfiability check, and the replay ASKS it rather than reproducing it.
  #
  # A stage whose query is a placeholder starts a record rather than a query, and every stage
  # asked of that record joins it. One record covers a query whose entity AND include name both
  # arrive at run time - the replay expands both, over the product of the two candidate sets.
  defp apply_query_stage!(function, [%Placeholder{} = base | rest_args], state, context) do
    {%SymbolicQuery{base: base, stages: [{function, rest_args, context.line}]}, state}
  end

  defp apply_query_stage!(function, [%SymbolicQuery{} = query | rest_args], state, context) do
    {%{query | stages: [{function, rest_args, context.line} | query.stages]}, state}
  end

  # An include name is the other position the window is derived from, so a query that is otherwise
  # concrete becomes a record here too - its candidates are its own entity's relationships.
  defp apply_query_stage!(
         :include,
         [query | [%Placeholder{} | _rest] = rest_args],
         state,
         context
       ) do
    {%SymbolicQuery{base: query, stages: [{:include, rest_args, context.line}]}, state}
  end

  defp apply_query_stage!(function, arg_values, state, context) do
    {apply_authored_stage!(function, arg_values, context), state}
  end

  defp relationship_names(%Query{entity: entity_type}), do: relationship_names(entity_type)

  # Every name an include takes, inverses included.
  defp relationship_names(entity_type) when is_atom(entity_type) do
    Entity.includable_names(entity_type)
  end

  # A stage call the developer wrote is theirs to read, so a refusal from it is reraised carrying
  # the prop it belongs to, which the error cannot know.
  defp apply_authored_stage!(function, arg_values, context) do
    apply(Stage, function, arg_values)
  rescue
    error in [ArgumentError, MisuseError] ->
      reraise Hologram.CompileError,
              [
                message: stage_error_message(function, arg_values, error, context),
                file: context_file(context),
                line: context.line,
                stack: context.stack
              ],
              __STACKTRACE__
  end

  # A Derived call builds a stand-in or a definition from others, so it runs natively - what it
  # refuses is the definition's to answer for, at the line the walk stood on.
  defp apply_derived!(function, arg_values, context) do
    apply(Derived, function, arg_values)
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
      unknown_value?(bound) or unknown_value?(value) -> {:cont, {:unknown, bindings}}
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

  # A call the field's own clause makes into another module is a query builder: followed into its
  # IR, whatever it is given, since it builds the query the definition is - so it returns a query
  # term.
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
      "#{context.subject} calls a function whose head destructures a parameter - only plain names, literals, and _ are extractable yet",
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
      "#{context.subject} uses a composite case pattern - only variables, literals, and _ are extractable yet",
      context
    )
  end

  # The clause a branch takes: the one candidate, or - when the build cannot tell which - a fork over
  # the candidates, which a derived field refuses. With none, the code raises where the branch is -
  # unless a fork made the values up, combining choices no run makes, so the variant is pruned.
  defp choose_clause!([], %{forked?: true}, _no_match, _context), do: throw(@prune_signal)

  defp choose_clause!([], _state, no_match, context), do: compile_error!(no_match, context)

  defp choose_clause!([index], state, _no_match, _context), do: {index, state}

  defp choose_clause!(candidates, state, _no_match, context) do
    refuse_undecided_branch!(context)

    {choice, state_after_choice} = take_choice!(state, length(candidates), context)

    {Enum.at(candidates, choice), state_after_choice}
  end

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

  defp contains_placeholder?(%Placeholder{}), do: true

  # A record is as unknown as the placeholder it stands on - a native call must never receive one.
  defp contains_placeholder?(%SymbolicQuery{}), do: true

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

  # The file a refusal is located in: the module being walked - or, in a derived field's own clause,
  # the file the field is declared in, which the clause is generated into.
  defp context_file(%{derived: %{at_field?: true, file: file}}), do: file

  defp context_file(context), do: source_file(context.current_module)

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

  # The clause of the entity type's __derived_definition__/1 the field's definition is built by.
  defp derived_clause!(entity_type, name, ir_plt) do
    {_fun_key, {_visibility, clauses}} =
      entity_type
      |> module_funs(ir_plt)
      |> List.keyfind({:__derived_definition__, 1}, 0)

    Enum.find(clauses, &match?(%IR.FunctionClause{params: [%IR.AtomType{value: ^name}]}, &1))
  end

  # Whether the walk stands in the derived field's own clause, where a builder is called from.
  defp derived_level?(%{derived: %{at_field?: true}}), do: true

  defp derived_level?(_context), do: false

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
      "#{context.subject} uses a multi-clause anonymous function - not extractable yet",
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

    {choice, state_after_choice} =
      choose_clause!(candidates, state_after_condition, no_match, context)

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
      %Placeholder{name: name} ->
        # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
        {%Placeholder{name: :"#{name}.#{field}"}, state_after_field}

      # The record's own shape is not known until it is replayed, so a read off one is unknowable
      # too - named for the argument it derives from, like every other value the build cannot see.
      %SymbolicQuery{} = query ->
        {%Placeholder{name: first_placeholder_name(query)}, state_after_field}

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

  defp evaluate!(%IR.MatchOperator{}, _state, context) do
    compile_error!(
      "#{context.subject} pattern-matches in its body - only plain variable binds are extractable yet",
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
      target_module in [Query, Stage] ->
        apply_query_stage!(function, arg_values, state_after_args, context)

      context.derived != nil and target_module == Derived ->
        {apply_derived!(function, arg_values, context), state_after_args}

      derived_level?(context) ->
        builder_call!(target_module, function, arg_values, state_after_args, context)

      stand_in?(arg_values) ->
        stand_in_call!(target_module, function, arg_values, state_after_args, context)

      not contains_placeholder?(arg_values) ->
        record_derived_read(target_module, context)

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

  # A variable is read by its name and version: the walk keeps every binding apart, so one the
  # compiler introduced - the x an if expands into - never hides the developer's own x.
  defp evaluate!(%IR.Variable{name: name, version: version}, state, _context) do
    {Map.fetch!(state.env, {name, version}), state}
  end

  defp evaluate!(ir, _state, context) do
    compile_error!(
      "#{context.subject} uses #{inspect(ir.__struct__)} - the construct is not extractable yet",
      context
    )
  end

  # A known condition decides its clause, as the cond does at runtime. An unknown one forks: one
  # variant takes the clause, the other goes on to the next. Past every clause the code raises -
  # unless a fork made the values up, so the variant is pruned.
  defp evaluate_cond!([], %{forked?: true}, _context), do: throw(@prune_signal)

  defp evaluate_cond!([], _state, context) do
    compile_error!(
      "#{context.subject} reaches a cond none of whose conditions holds - the code raises CondClauseError there",
      context
    )
  end

  defp evaluate_cond!([clause | rest], state, context) do
    {condition_value, state_after_condition} = evaluate!(clause.condition, state, context)

    cond do
      unknown_value?(condition_value) ->
        refuse_undecided_branch!(context)

        {choice, state_after_choice} = take_choice!(state_after_condition, 2, context)

        if choice == 0 do
          evaluate_cond_body!(clause, state_after_choice, context)
        else
          evaluate_cond!(rest, state_after_choice, context)
        end

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

  defp evaluate_variants!(body, env, context, choices, forked?) do
    result =
      try do
        {term, _state} =
          evaluate!(
            body,
            %{choices: choices, env: env, forked?: forked?, funs_cache: %{}},
            context
          )

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
          evaluate_variants!(body, env, context, List.insert_at(choices, -1, choice), forked?)
        end)
    end
  end

  defp fetch_function_clauses!(funs, module, function, arity, context) do
    case List.keyfind(funs, {function, arity}, 0) do
      {_fun_key, {_visibility, clauses}} ->
        clauses

      nil ->
        compile_error!(
          "#{context.subject} calls undefined function #{inspect(module)}.#{function}/#{arity}",
          context
        )
    end
  end

  # A computed value carries the name of the argument it derives from - the first one reached, and
  # any of them says the same thing about the term: this is not knowable until the query runs. The
  # name never reaches a window id (Hologram.Query.Window drops what a placeholder stands in), so what it
  # is FOR is saying which argument the value came from when a term is read.
  defp first_placeholder_name(%Placeholder{name: name}), do: name

  defp first_placeholder_name(%SymbolicQuery{base: base, stages: stages}) do
    first_placeholder_name(base) || first_placeholder_name(Enum.map(stages, &elem(&1, 1)))
  end

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
      {:ok, value} -> if unknown_value?(value), do: :unknown, else: {:known, value}
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

  # A guard construct the walk does not evaluate leaves a capture's clause undecided, forked as any
  # other. A derived field's walk has to decide it, so there it is refused for what it is.
  defp guard_value(_ir, _env, %{derived: nil}), do: :unknown

  defp guard_value(ir, _env, context) do
    compile_error!(
      "#{context.subject} uses #{inspect(ir.__struct__)} in a guard - the construct is not extractable yet",
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

  # TODO: an argument named vars will bind the full assigns bag once that
  # convention lands - until then the name is reserved.
  defp head_binding!(module, prop_name, %IR.Variable{name: :vars}, line) do
    compile_error!(
      "query capture for prop #{inspect(prop_name)} in #{inspect(module)} names an argument vars - the name is reserved, name arguments after the component assigns they bind to",
      module,
      line
    )
  end

  defp head_binding!(_module, _prop_name, %IR.Variable{name: name, version: version}, _line) do
    {{name, version}, %Placeholder{name: name}}
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

    state = %{choices: :none, env: call_env, forked?: false, funs_cache: %{}}

    {value, _state} = evaluate!(clause.body, state, context)

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
        "#{context.subject} recursively calls #{inspect(module)}.#{function}/#{arity} - recursive helpers are not extractable",
        context
      )
    end

    record_derived_read(module, context)

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

    no_match =
      "#{context.subject} calls #{inspect(module)}.#{function}/#{arity} with #{Enum.map_join(arg_values, ", ", &spelled_argument/1)}, which no clause matches - the code raises FunctionClauseError there"

    {choice, state_after_choice} = choose_clause!(candidates, state_after_funs, no_match, context)

    clause = Enum.at(clauses, choice)
    call_env = call_env!(clause.params, arg_values, %{}, context)
    # The line starts unknown in the function being entered - the caller's line belongs to the
    # caller's frame, and pairing it with the callee's file would name a line in the wrong module.
    new_context = %{
      context
      | current_module: module,
        derived: leave_field(context.derived),
        line: nil,
        stack: [frame(module, function, arity, nil) | context.stack]
    }

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

  # What the developer asked for, read off the record rather than off the candidates' refusals: the
  # first candidate of a build is a framework entity type, so quoting ITS refusal would answer a
  # question about the developer's model with the grant store's columns.
  defp no_window_refusal(module, prop_name, variants) do
    prefix = "query capture for prop #{inspect(prop_name)} in #{inspect(module)}"
    tail = "a prop with no window would read rows nothing ever fills"

    case Enum.find_value(variants, &relationshipless_include/1) do
      nil ->
        {clause, line} = asked_for(variants)

        {"#{prefix} builds no query that any entity type of the build admits#{clause} - #{tail}",
         line}

      {entity_type, line} ->
        {"#{prefix} includes a relationship of #{inspect(entity_type)}, which declares none - #{tail}",
         line}
    end
  end

  defp asked_for(variants) do
    case Enum.find_value(variants, &filtered_names/1) do
      nil ->
        {"", nil}

      {names, line} ->
        {" - it filters on #{Enum.map_join(names, ", ", &Stage.inspect_name/1)}", line}
    end
  end

  defp filtered_names(%SymbolicQuery{stages: stages}) do
    stages
    |> Enum.reverse()
    |> Enum.find_value(&filter_stage_names/1)
  end

  defp filtered_names(_variant), do: nil

  defp filter_stage_names({:filter, [predicates], line}) when is_list(predicates) do
    names =
      predicates
      |> Stage.written_names()
      |> Enum.uniq()

    if names == [], do: nil, else: {names, line}
  end

  defp filter_stage_names(_stage), do: nil

  # An include name the build cannot enumerate is not an unknowable position - its candidate set is
  # simply empty, which only the entity it was asked of can explain.
  defp relationshipless_include(%SymbolicQuery{base: %Placeholder{}}), do: nil

  defp relationshipless_include(%SymbolicQuery{base: base, stages: stages}) do
    if relationship_names(base) == [] do
      empty_include_refusal(base, stages)
    end
  end

  defp relationshipless_include(_variant), do: nil

  defp empty_include_refusal(base, stages) do
    case Enum.find_value(stages, &include_placeholder_line/1) do
      nil -> nil
      line -> {entity_type(base), line}
    end
  end

  defp include_placeholder_line({:include, [%Placeholder{} | _rest_args], line}), do: line

  defp include_placeholder_line(_stage), do: nil

  defp entity_type(%Query{entity: entity_type}), do: entity_type

  defp entity_type(entity_type) when is_atom(entity_type), do: entity_type

  defp known_values(values), do: Enum.map(values, fn {:known, value} -> value end)

  # A position named by some clauses and left a literal by others merges to the one name - that is
  # what this is for, and it is how a `def q(nil)` clause sits beside a `def q(min_b)` one. Two
  # clauses naming it DIFFERENTLY is the shape that cannot merge, since the caller must pick a
  # prop's value before any clause is chosen.
  # A function the walk enters is no derived field's own clause, wherever it is defined.
  defp leave_field(nil), do: nil

  defp leave_field(derived), do: %{derived | at_field?: false}

  defp map_of_pairs(flat_pairs) do
    flat_pairs
    |> Enum.chunk_every(2)
    |> Map.new(fn [key, value] -> {key, value} end)
  end

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

  # A module the PLT holds is read from it, one it lacks is built into it, so that the next read of
  # it, by this extraction or another, finds it. Looked up before the build is asked for: building
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

  defp param_name(clause, index) do
    case Enum.at(clause.params, index) do
      %IR.Variable{name: name} -> name
      _pattern -> nil
    end
  end

  # Whether a clause head's pattern matches a value: always for a name or _, by the literal's equality
  # for a literal - unknown when the build does not know the value - with the bindings it makes.
  defp pattern_outcome(%IR.Variable{name: name, version: version}, value, _binder),
    do: {:match, %{{name, version} => value}}

  defp pattern_outcome(%IR.MatchPlaceholder{}, _value, _binder), do: {:match, %{}}

  defp pattern_outcome(%{__struct__: struct, value: literal}, value, _binder)
       when struct in [IR.AtomType, IR.FloatType, IR.IntegerType, IR.StringType] do
    cond do
      unknown_value?(value) -> {:unknown, %{}}
      value === literal -> {:match, %{}}
      true -> :no_match
    end
  end

  defp pattern_outcome(pattern, _value, binder), do: binder.(pattern)

  defp prop_params(module, {name, _type, opts}, ir_plt) do
    with {:ok, capture} <- Keyword.fetch(opts, :from_query),
         true <- is_function(capture) and not is_function(capture, 0) do
      {_target_module, _fun_name, _arity, clauses} =
        resolve_capture_clauses!(module, name, capture, ir_plt)

      arity = Function.info(capture)[:arity]

      [{name, merged_placeholder_names(module, name, clauses, arity)}]
    else
      _absent_zero_arity_or_non_capture -> []
    end
  end

  defp module_funs_cached(module, state, ir_plt) do
    case state.funs_cache do
      %{^module => funs} ->
        {funs, state}

      _missing ->
        funs = module_funs(module, ir_plt)

        {funs, %{state | funs_cache: Map.put(state.funs_cache, module, funs)}}
    end
  end

  defp prop_queries!(module, {name, _type, opts}, entity_types, ir_plt) do
    case Keyword.fetch(opts, :from_query) do
      {:ok, capture} -> prop_query!(module, name, capture, entity_types, ir_plt)
      :error -> []
    end
  end

  defp prop_query!(_module, _prop_name, capture, _entity_types, _ir_plt)
       when is_function(capture, 0) do
    [Stage.normalize(capture.())]
  end

  defp prop_query!(module, prop_name, capture, entity_types, ir_plt) when is_function(capture) do
    {target_module, fun_name, arity, clauses} =
      resolve_capture_clauses!(module, prop_name, capture, ir_plt)

    # The capture's own frame opens the stack, so a refusal in its body has a path to show even
    # when it called nothing - the innermost frame is always the function being walked, which is
    # what makes the whole list read as a stacktrace rather than a list of callers.
    context = %{
      current_module: target_module,
      derived: nil,
      entity_types: entity_types,
      ir_plt: ir_plt,
      line: nil,
      stack: [frame(target_module, fun_name, arity, nil)],
      subject: "query capture for prop #{inspect(prop_name)} in #{inspect(module)}"
    }

    variants =
      Enum.flat_map(clauses, fn clause ->
        env = head_env!(module, prop_name, clause)

        evaluate_variants!(clause.body, env, context, [], length(clauses) > 1)
      end)

    terms =
      variants
      |> Enum.flat_map(&resolve(&1, entity_types))
      |> Enum.map(&Stage.normalize/1)
      |> Enum.uniq()

    if terms == [] do
      {message, line} = no_window_refusal(module, prop_name, variants)

      compile_error!(message, target_module, line || hd(clauses).line)
    end

    terms
  end

  defp prop_query!(module, prop_name, value, _entity_types, _ir_plt) do
    compile_error!(
      "from_query for prop #{inspect(prop_name)} in #{inspect(module)} must be a function capture, got: #{inspect(value)}",
      module,
      nil
    )
  end

  # A project module whose function a derived field's walk follows or runs is one whose edit can
  # change the definition - Elixir's own modules never change between compiles of an app.
  defp record_derived_read(_module, %{derived: nil}), do: :ok

  defp record_derived_read(module, _context) do
    if interpretable_module?(module) do
      Process.put(@derived_reads_key, MapSet.put(Process.get(@derived_reads_key), module))
    end

    :ok
  end

  # A derived field's definition is built once, before any row is read, so a branch the build cannot
  # decide is one on a field of the row - the one value a derived field's walk does not know.
  defp refuse_undecided_branch!(%{derived: nil}), do: :ok

  defp refuse_undecided_branch!(context) do
    compile_error!(
      "#{context.subject} branches on a field of the row - a derived field's definition is one query, built before any row is read",
      context
    )
  end

  # Every stage runs inside the rescue, and the rescue covers the whole continuation - so a
  # candidate refused by a LATER stage drops out here rather than failing the build, however deep
  # the refusal happens. A later stage refusing the candidate a replay chose is the replay's
  # problem, not the developer's, which is what apply_authored_stage!/3 keeps loud for a query the
  # developer wrote concretely.
  defp replay([], query), do: [query]

  defp replay([{:include, [%Placeholder{} | rest_args], _line} | rest_stages], query) do
    query
    |> relationship_names()
    |> Enum.flat_map(&replay_stage(rest_stages, query, :include, [&1 | rest_args]))
  end

  defp replay([{function, args, _line} | rest_stages], query) do
    replay_stage(rest_stages, query, function, args)
  end

  defp replay_stage(rest_stages, query, function, args) do
    replay(rest_stages, apply(Stage, function, [query | args]))
  rescue
    ArgumentError -> []
    Hologram.CompileError -> []
    MisuseError -> []
  end

  # A record becomes the queries it admits: over every entity type of the build when the entity
  # itself is unknown, over the one it already names when only an include name is.
  defp resolve(%SymbolicQuery{base: %Placeholder{}, stages: stages}, entity_types) do
    Enum.flat_map(entity_types, &replay(Enum.reverse(stages), &1))
  end

  defp resolve(%SymbolicQuery{base: base, stages: stages}, _entity_types) do
    replay(Enum.reverse(stages), base)
  end

  defp resolve(term, _entity_types), do: [term]

  defp resolve_capture_clauses!(prop_module, prop_name, capture, ir_plt) do
    capture_info = Function.info(capture)
    target_module = capture_info[:module]

    fun_name = shim_target(target_module, capture_info[:name])
    arity = capture_info[:arity]

    funs = module_funs(target_module, ir_plt)

    case List.keyfind(funs, {fun_name, arity}, 0) do
      {_fun_key, {_visibility, clauses}} ->
        {target_module, fun_name, arity, clauses}

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

  # An argument as a message spells it: a value the build knows as inspect/1 does, one it does not
  # by the name of the argument it stands for.
  defp spelled_argument(%Placeholder{name: name}), do: Atom.to_string(name)

  defp spelled_argument(value), do: inspect(value)

  defp stage_error_message(function, arg_values, error, context) do
    prefix = context.subject

    if contains_placeholder?(arg_values) do
      "#{prefix} passes an argument to #{function}/#{length(arg_values)} in a position the build cannot enumerate - the rows to download cannot be worked out without its value"
    else
      "#{prefix} builds an invalid query - #{Exception.message(error)}"
    end
  end

  # Whether a value holds a stand-in for a field of the row a derived field is computed for.
  defp stand_in?(%RowField{}), do: true

  defp stand_in?(%RowRef{}), do: true

  defp stand_in?(%Query{source: source}), do: source != nil

  defp stand_in?(list) when is_list(list), do: Enum.any?(list, &stand_in?/1)

  defp stand_in?(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> stand_in?()
  end

  defp stand_in?(map) when is_map(map) do
    map
    |> Map.values()
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
  # There is always one: the capture's own frame opens the stack before its body is walked.
  defp relocated_stack([{module, function, arity, _location} | rest_frames], line) do
    [frame(module, function, arity, line) | rest_frames]
  end

  defp take_choice!(%{choices: [choice | rest]} = state, _clause_count, _context) do
    {choice, %{state | choices: rest, forked?: true}}
  end

  defp take_choice!(%{choices: []}, clause_count, _context) do
    throw({@fork_signal, clause_count})
  end

  defp take_choice!(%{choices: :none}, _clause_count, context) do
    compile_error!(
      "#{context.subject} branches inside an anonymous function - not extractable yet",
      context
    )
  end

  defp unknown_value?(value), do: contains_placeholder?(value) or stand_in?(value)

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

  defp weaker(:match, outcome), do: outcome

  defp weaker(:unknown, _outcome), do: :unknown
end
