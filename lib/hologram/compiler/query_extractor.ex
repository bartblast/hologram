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

  # Where a component or page derived field's walk built queries with query stages, in walk order,
  # and which of those places a later stage, a function of the project or a variant's result took -
  # across every variant of the field, since a query one variant drops another may return. `values`
  # maps the queries of the variant being walked to where they were built. Gathered across the
  # closures the walk runs.
  @derived_stages_key {__MODULE__, :derived_stages}

  # Fork enumeration uses throw for non-local exit: on an undecided branch the
  # evaluation aborts, and the driver restarts it from the body with one more
  # branch choice appended (depth-first over the choice tree).
  @fork_signal :hologram_query_extractor_fork
  @prune_signal :hologram_query_extractor_prune

  defmodule SymbolicQuery do
    @moduledoc false

    # A query the build cannot execute yet, because a position the WINDOW is derived from - the
    # entity that says which table to download, an include name that says which relationship
    # travels with it - is an argument. Nothing is built while the function is walked: each stage
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
  query builder is resolved, since the builder is written for the values it will be given, and a
  field of the row has none while the definition is built.

  What the walk reads stands in for the row's fields as `Hologram.Entity.Derived.field/2` builds
  them - a query over a set, a row field, a related row - and goes where a query goes: query stages
  and `Hologram.Entity.Derived` run natively over them, a call into the entity type's own functions or
  another module of the project is followed into its IR with them, and a dot on a related row reads the longer path. The result is
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
      [definition] = evaluate_variants!(clause.body, %{}, context, [])

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
  Extracts the registered query terms of the given component or page module's derived fields, each
  field's name with the normalized terms its function builds - leaving out a field whose function
  builds no query, which holds a plain value.

  A field's function builds a query when it, or a function of the project it calls, calls a query
  stage, or returns an entity type, which stands for every row of it. Any other function is not
  walked: what it computes is plain Elixir, which the build has no need to follow.

  A function that builds a query is evaluated symbolically over its IR - each argument becomes a
  placeholder flowing into the term as a `{:placeholder, name}` leaf named after the field it
  reads. A branch on a value the build knows - a case, a cond, a call to a multi-clause helper -
  takes the clause that value takes, its patterns and guards read in order as Elixir reads them,
  and a known value no clause matches is refused where the code would raise. A branch on an
  argument forks the evaluation: every clause the value could take yields its own variant term,
  and all variants are extracted (deduplicated per field) - a variant that cannot occur at runtime
  is over-approximation, costing a registry entry, never correctness. Every variant must be a
  query.

  Calls interpret transitively: local helpers and placeholder-receiving functions compiled into
  the project build evaluate over their own IR (recursion is rejected), placeholder-free remote
  calls and query stage calls run natively, and single-clause anonymous functions evaluate on
  invocation with their captured scope (a branch inside one only on a value the build knows).

  ANYTHING THE BUILD CAN EVALUATE IS PART OF THE QUERY, ANYTHING IT CANNOT IS A PLACEHOLDER. That
  is the whole rule, and what it serves is the sync window - which rows a client downloads - never
  validation, which happens when the query runs against real values on either tier. A call the
  build cannot make yields a placeholder named for the argument it derives from.

  Where a placeholder may land follows from the window, not from the term. A position
  `Hologram.Query.Window` drops or empties takes one as a leaf: a filter attribute or value, an
  ordering key or direction, a view bound. A position the window is DERIVED from cannot - the
  entity says which table to download, an include name says which relationship travels with it -
  so a query holding one is not built while the function is walked at all: the stages asked of it
  are RECORDED, and the record is replayed through the builder once per candidate of a finite set
  (every entity type of the build, or the query's entity's declared relationships), keeping the
  variants the builder admits and, over entity types, the ones the field's type names. The
  developer's code is walked once, and only the recorded stages are replayed. What narrows the set
  is the builder's own validation, whatever stage refuses: `filter(entity_type, done: false)` keeps
  precisely the types declaring a boolean `done`, and a candidate a LATER stage cannot satisfy - an
  entity declaring no relationship to include - is dropped rather than failing the build.

  Raises Hologram.CompileError when a field's function builds a query but returns something else, a
  query of another shape than the field's type - a set of rows, one row or a count - or of another
  entity type, a query over another derived field's rows, a query used as a value, when a case
  clause or function head uses a composite pattern, when a known value matches no clause, when a
  helper recurses, when an anonymous function has multiple clauses, arity above 3, or a branch on
  an argument, when a body uses a construct symbolic evaluation does not cover, when a placeholder
  stands somewhere the build can neither drop nor enumerate (a whole predicates list, a paginate
  option map), or when no candidate survives - a derived field with no window would read rows
  nothing ever fills.

  The entity types are the replay's candidate set for a placeholder in an entity position. They
  are taken as an argument so that a build computes them once and passes the one list to every
  extraction, rather than every extraction reading them.

  The IR a function is walked over is read from the given IR PLT, the compile's: a module the PLT
  lacks is built into it (see Hologram.Compiler.build_missing_ir!/2), so that no module's IR is
  built twice in a compile.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/query_extractor/extract_derived_queries_3/README.md
  """
  @spec extract_derived_queries(module, list(module), PLT.t()) :: [{atom, [Query.t()]}]
  def extract_derived_queries(module, entity_types, ir_plt) do
    if Reflection.has_function?(module, :__derived__, 0) do
      derived_names = Enum.map(module.__derived__(), & &1.name)

      module.__derived__()
      |> Enum.filter(&builds_query?(&1.function, entity_types, ir_plt))
      |> Enum.map(fn entry ->
        {entry.name, derived_queries!(module, entry, derived_names, entity_types, ir_plt)}
      end)
    else
      []
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
    refuse_derived_rows_source!(base, context)

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

  # A dot on a placeholder names the read it stands for after the argument, so the argument is the
  # name's root.
  defp refuse_derived_rows_source!(%Placeholder{name: name}, context) do
    root =
      name
      |> Atom.to_string()
      |> String.split(".")
      |> hd()

    case Map.get(context, :derived_value) do
      %{inputs: inputs, subject: subject} ->
        input = Enum.find(inputs, &(Atom.to_string(&1) == root))

        if input do
          compile_error!(
            "#{subject} runs a query over derived field #{inspect(input)}'s rows - a query reads an entity type, so filter the rows in Elixir or build the query from the same inputs",
            context
          )
        end

      nil ->
        :ok
    end

    :ok
  end

  defp relationship_names(%Query{entity: entity_type}), do: relationship_names(entity_type)

  # Every name an include takes, inverses included.
  defp relationship_names(entity_type) when is_atom(entity_type) do
    Entity.includable_names(entity_type)
  end

  # A stage call the developer wrote is theirs to read, so a refusal from it is reraised carrying
  # the derived field it belongs to, which the error cannot know.
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

  defp body_reaches_query?(body, {_reaches?, seen}, module, tail?, entity_types, ir_plt) do
    # The id tells this body's binds from another's: a variable's version is unique within a
    # function only.
    scope = %{bindings: plain_binds(body, %{}), id: make_ref(), module: module}

    case scan_reaches_query?([{body, tail?}], scope, entity_types, ir_plt, seen) do
      {true, next_seen} -> {:halt, {true, next_seen}}
      {false, next_seen} -> {:cont, {false, next_seen}}
    end
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

  # Whether the given derived field's function builds a query - calls a query stage, or returns an
  # entity type, itself or through a function of the project it calls. Only the IR is read, nothing
  # is run, so a function computing a plain value costs the build nothing.
  defp builds_query?(capture, entity_types, ir_plt) do
    info = Function.info(capture)
    mfa = {info[:module], info[:name], info[:arity]}

    {reaches?, _seen} = reaches_query?(mfa, true, entity_types, ir_plt, MapSet.new())

    reaches?
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

  defp contains_query?(value), do: queries_in(value) != []

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

  defp derived_call?(module, context), do: context.derived != nil and module == Derived

  # Whether the walk stands in the derived field's own clause, where a builder is called from.
  defp derived_level?(%{derived: %{at_field?: true}}), do: true

  defp derived_level?(_context), do: false

  defp derived_queries!(module, entry, derived_names, entity_types, ir_plt) do
    info = Function.info(entry.function)
    target_module = info[:module]

    {_fun_key, {_visibility, [clause]}} =
      target_module
      |> module_funs(ir_plt)
      |> List.keyfind({info[:name], info[:arity]}, 0)

    subject = "derived field #{inspect(entry.name)} in #{inspect(module)}"

    context = %{
      current_module: target_module,
      derived: nil,
      derived_value: %{inputs: Enum.filter(entry.args, &(&1 in derived_names)), subject: subject},
      entity_types: entity_types,
      ir_plt: ir_plt,
      line: nil,
      stack: [frame(target_module, info[:name], info[:arity], clause.line)],
      subject: subject
    }

    env = head_env(clause)

    variants =
      try do
        Process.put(@derived_stages_key, %{places: %{}, used: MapSet.new(), values: %{}})

        walked_variants = evaluate_variants!(clause.body, env, context, [])
        refuse_dropped_queries!(context)

        walked_variants
      after
        Process.delete(@derived_stages_key)
      end

    terms =
      variants
      |> Enum.flat_map(
        &derived_variant_terms!(&1, entry, subject, module, clause.line, entity_types)
      )
      |> Enum.uniq()

    if terms == [] do
      {message, line} =
        no_window_refusal(
          subject,
          "a derived field with no window would read rows nothing ever fills",
          variants
        )

      compile_error!(message, target_module, line || clause.line)
    end

    terms
  end

  # A query over an entity type a placeholder holds is replayed over every entity type, and the
  # replays the field's type doesn't name are dropped - the type is what pins the entity the
  # runtime reads, which checks the term against the type again. Every other query is the one term
  # it is, and has to match.
  defp derived_variant_terms!(
         %SymbolicQuery{base: %Placeholder{}} = query,
         entry,
         subject,
         module,
         line,
         entity_types
       ) do
    replays =
      query
      |> resolve(entity_types)
      |> Enum.map(&Stage.normalize/1)

    case Enum.filter(replays, &query_of_type?(&1, entry.type)) do
      [] when replays != [] ->
        compile_error!(
          "#{subject} is declared #{inspect(entry.type)}, but its query, over the entity type #{query.base.name} holds, is never #{type_description(entry.type)}",
          module,
          line
        )

      matching ->
        matching
    end
  end

  defp derived_variant_terms!(variant, entry, subject, module, line, entity_types) do
    cond do
      is_struct(variant, Query) or is_struct(variant, SymbolicQuery) or variant in entity_types ->
        variant
        |> resolve(entity_types)
        |> Enum.map(&Stage.normalize/1)
        |> Enum.map(&validate_derived_term!(&1, entry, subject, module, line))

      contains_query?(variant) ->
        compile_error!(query_as_value_message(subject), module, line)

      true ->
        compile_error!(
          "#{subject} builds a query, but returns #{spelled_value(variant)} - a derived field holding rows returns the query, and a value computed from the rows is a derived field of its own",
          module,
          line
        )
    end
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

  # An interpolation in a derived field is walked for what it interpolates, so a query among it is
  # refused as a value. Strings the build knows join into the string the code builds, and one
  # interpolating a value the build doesn't know is only known at runtime.
  defp evaluate!(
         %IR.BitstringType{segments: segments, line: line},
         state,
         %{derived_value: _derived_value} = context
       ) do
    context = with_line(context, line)

    {values, new_state} =
      segments
      |> Enum.map(& &1.value)
      |> evaluate_enum!(state, context)

    known_string? =
      Enum.all?(values, &is_binary/1) and
        Enum.all?(segments, &(&1.modifiers in [[type: :binary], [type: :utf8]]))

    cond do
      contains_placeholder?(values) ->
        {%Placeholder{name: first_placeholder_name(values)}, new_state}

      known_string? ->
        {Enum.join(values), new_state}

      true ->
        compile_error!(
          "#{context.subject} uses #{inspect(IR.BitstringType)} - the construct is not extractable yet",
          context
        )
    end
  end

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
  # Nothing executes the extracted term - both tiers call the real function with the component's
  # real field values - so the leaf only has to say that the value is unknown until the query runs.
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

    # In a derived field's own clause a local call is the entity type's own query builder, held to
    # what a builder of another module is.
    if derived_level?(context) do
      builder_call!(context.current_module, function, arg_values, state_after_args, context)
    else
      interpret_call!(context.current_module, function, arg_values, state_after_args, context)
    end
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

  # A match on _ or an underscored name in a derived field binds nothing, so only the right side is
  # walked.
  defp evaluate!(
         %IR.MatchOperator{left: %IR.MatchPlaceholder{}, right: right, line: line},
         state,
         %{derived_value: _derived_value} = context
       ) do
    evaluate!(right, state, with_line(context, line))
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
        {value, state_after_stage} =
          apply_query_stage!(function, arg_values, state_after_args, context)

        record_stage(arg_values, value, context)

        {value, state_after_stage}

      derived_call?(target_module, context) ->
        {apply_derived!(function, arg_values, context), state_after_args}

      derived_level?(context) ->
        builder_call!(target_module, function, arg_values, state_after_args, context)

      stand_in?(arg_values) ->
        stand_in_call!(target_module, function, arg_values, state_after_args, context)

      not contains_placeholder?(arg_values) ->
        record_derived_read(target_module, context)

        {native_call!(target_module, function, arg_values, context), state_after_args}

      interpretable_module?(target_module) ->
        interpret_call!(target_module, function, arg_values, state_after_args, context)

      # What the call does with a query it is given is only known at runtime, and so is what it
      # returns.
      true ->
        record_used_queries(arg_values, context)

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

  defp evaluate_variants!(body, env, context, choices) do
    result =
      try do
        reset_derived_stages(context)

        {term, _state} =
          evaluate!(
            body,
            %{choices: choices, env: env, forked?: false, funs_cache: %{}},
            context
          )

        record_returned(term, context)

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
          undefined_function_message(context.subject, module, function, arity),
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

  # Hologram's own modules answer what an app asks of them - can?/3 reads grants through queries of
  # its own - so a call into one builds no query of the field's. The suite's fixtures are compiled
  # into the same application, under Hologram.Test.
  defp framework_module?(module) do
    test_module? =
      module
      |> Atom.to_string()
      |> String.starts_with?("Elixir.Hologram.Test.")

    :application.get_application(module) == {:ok, :hologram} and not test_module?
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

  # A guard construct the walk does not evaluate leaves the clause undecided in a component derived
  # field's walk, forked as any other. An entity derived field's walk has to decide it, so there it
  # is refused for what it is.
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

  # A derived field's function names the fields it reads, so each argument is a placeholder named
  # for its field. An underscored name reads a field the function doesn't use, and binds nothing.
  defp head_env(clause) do
    clause.params
    |> Enum.flat_map(fn
      %IR.Variable{name: name, version: version} -> [{{name, version}, %Placeholder{name: name}}]
      %IR.MatchPlaceholder{} -> []
    end)
    |> Map.new()
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

    no_match = no_clause_message(context.subject, module, function, arg_values)

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
  defp no_window_refusal(prefix, tail, variants) do
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

  # A function the walk enters is no derived field's own clause, wherever it is defined.
  defp leave_field(nil), do: nil

  defp leave_field(derived), do: %{derived | at_field?: false}

  defp map_of_pairs(flat_pairs) do
    flat_pairs
    |> Enum.chunk_every(2)
    |> Map.new(fn [key, value] -> {key, value} end)
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

  # A call the build runs for real. In a derived field's walk, a call that fails on a query it was
  # given used the query as a value - iterated its rows, measured it, turned it into a string - and a
  # function of the project that took one without failing is a builder, which took it as its source.
  defp native_call!(module, function, arg_values, %{derived_value: _derived_value} = context) do
    value = apply(module, function, arg_values)

    if interpretable_module?(module) do
      record_used_queries(arg_values, context)
    end

    value
  rescue
    error -> native_failure!(error, __STACKTRACE__, context)
  end

  defp native_call!(module, function, arg_values, _context),
    do: apply(module, function, arg_values)

  # A call the build ran failed. A function that doesn't exist, or one of the project or a dependency
  # that no clause of matches, is reported as the walk reports one it follows. A call that failed on
  # a query it was given used the query as a value. Any other failure is the app's own.
  defp native_failure!(%UndefinedFunctionError{} = error, _stacktrace, context) do
    message =
      undefined_function_message(context.subject, error.module, error.function, error.arity)

    compile_error!(message, context)
  end

  @spec native_failure!(Exception.t(), Exception.stacktrace(), map) :: no_return
  defp native_failure!(error, stacktrace, context) do
    cond do
      project_clause_failure?(error, stacktrace) ->
        [{module, function, args, _location} | _frames] = stacktrace
        compile_error!(no_clause_message(context.subject, module, function, args), context)

      query_failure?(error, stacktrace) ->
        compile_error!(query_as_value_message(context.subject), context)

      true ->
        reraise error, stacktrace
    end
  end

  defp no_clause_message(subject, module, function, arg_values) do
    "#{subject} calls #{inspect(module)}.#{function}/#{length(arg_values)} with #{Enum.map_join(arg_values, ", ", &spelled_argument/1)}, which no clause matches - the code raises FunctionClauseError there"
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

  defp module_funs_cached(module, state, ir_plt) do
    case state.funs_cache do
      %{^module => funs} ->
        {funs, state}

      _missing ->
        funs = module_funs(module, ir_plt)

        {funs, %{state | funs_cache: Map.put(state.funs_cache, module, funs)}}
    end
  end

  # The plain binds a function body makes, by variable: what a variable the field's result comes
  # from holds, so the scan follows it there. A variable is bound once at each version, so one map
  # holds every bind of the body, the ones inside its branches and functions too.
  defp plain_binds(
         %IR.MatchOperator{left: %IR.Variable{name: name, version: version}, right: right},
         binds
       ),
       do: plain_binds(right, Map.put(binds, {name, version}, right))

  defp plain_binds(node, binds) when is_struct(node) do
    node
    |> Map.from_struct()
    |> Map.values()
    |> plain_binds(binds)
  end

  defp plain_binds(node, binds) when is_list(node), do: Enum.reduce(node, binds, &plain_binds/2)

  defp plain_binds(node, binds) when is_tuple(node) do
    node
    |> Tuple.to_list()
    |> plain_binds(binds)
  end

  defp plain_binds(_node, binds), do: binds

  # A function of the project or a dependency fails on a clause it doesn't have for its arguments,
  # whichever of them it is - the walk reports that as it reports a clause it follows.
  defp project_clause_failure?(
         %FunctionClauseError{module: module, function: function},
         [{module, function, args, _location} | _frames]
       )
       when is_list(args),
       do: interpretable_module?(module)

  defp project_clause_failure?(_error, _stacktrace), do: false

  # The queries a value holds, itself one or inside lists, tuples, maps and structs.
  defp queries_in(%Query{} = query), do: [query]

  defp queries_in(%SymbolicQuery{} = query), do: [query]

  defp queries_in(list) when is_list(list), do: Enum.flat_map(list, &queries_in/1)

  defp queries_in(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> queries_in()
  end

  defp queries_in(map) when is_map(map) do
    map
    |> Map.to_list()
    |> queries_in()
  end

  defp queries_in(_other), do: []

  defp query_as_value_message(subject) do
    "#{subject} uses a query as a value - a query describes rows, so declare it as a derived field and read that"
  end

  defp query_description(%Query{cardinality: :count, entity: entity}),
    do: "a count of #{inspect(entity)} rows"

  defp query_description(%Query{cardinality: :one, entity: entity}),
    do: "one #{inspect(entity)} row"

  defp query_description(%Query{entity: entity}), do: "a set of #{inspect(entity)} rows"

  # A call fails on a query it was given when a protocol the query doesn't implement was asked of it -
  # Enumerable, String.Chars - or when an Erlang or Elixir function was handed it in place of a list,
  # a number or a string, which its frame shows with the arguments it was called with.
  defp query_failure?(%Protocol.UndefinedError{value: value}, _stacktrace),
    do: contains_query?(value)

  defp query_failure?(_error, [{_module, _function, args, _location} | _frames])
       when is_list(args),
       do: contains_query?(args)

  defp query_failure?(_error, _stacktrace), do: false

  defp query_of_type?(%Query{cardinality: :set, entity: entity}, [entity]), do: true

  defp query_of_type?(%Query{cardinality: :one, entity: entity}, entity), do: true

  defp query_of_type?(%Query{cardinality: :count}, :integer), do: true

  defp query_of_type?(_term, _type), do: false

  @spec raise_derived_type_mismatch!(Query.t(), map, String.t(), module, pos_integer | nil) ::
          no_return
  defp raise_derived_type_mismatch!(term, entry, subject, module, line) do
    compile_error!(
      "#{subject} is declared #{inspect(entry.type)}, but its query is #{query_description(term)}",
      module,
      line
    )
  end

  # Whether the given function calls a query stage, or returns an entity type when its result is the
  # field's (tail? true), itself or through the functions of the project it calls - each walked once
  # per position, so recursion ends.
  defp reaches_query?({module, function, arity} = mfa, tail?, entity_types, ir_plt, seen) do
    key = {mfa, tail?}

    if MapSet.member?(seen, key) do
      {false, seen}
    else
      seen = MapSet.put(seen, key)

      fun =
        module
        |> module_funs(ir_plt)
        |> List.keyfind({function, arity}, 0)

      case fun do
        {_fun_key, {_visibility, clauses}} ->
          bodies = Enum.map(clauses, & &1.body)

          Enum.reduce_while(
            bodies,
            {false, seen},
            &body_reaches_query?(&1, &2, module, tail?, entity_types, ir_plt)
          )

        nil ->
          {false, seen}
      end
    end
  end

  # A query the walk built is kept with where it was built, in walk order, and among the queries of
  # the variant being walked, so a later use of it finds the place.
  defp record_built(value, context) do
    if is_struct(value, Query) or is_struct(value, SymbolicQuery) do
      stages = Process.get(@derived_stages_key)
      key = {context_file(context), context.line}

      place = %{
        file: context_file(context),
        line: context.line,
        order: map_size(stages.places),
        stack: context.stack
      }

      Process.put(@derived_stages_key, %{
        stages
        | places: Map.put_new(stages.places, key, place),
          values: Map.update(stages.values, value, [key], &[key | &1])
      })
    end

    :ok
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

  # A query a variant returns is the field's query, so the place that built it is used.
  defp record_returned(term, %{derived_value: _derived_value} = context) do
    if is_struct(term, Query) or is_struct(term, SymbolicQuery) do
      record_used_queries([term], context)
    end

    :ok
  end

  defp record_returned(_term, _context), do: :ok

  # A stage takes its query argument as its source, and the query it builds is kept with where it
  # was built.
  defp record_stage(arg_values, value, %{derived_value: _derived_value} = context) do
    record_used_queries(Enum.take(arg_values, 1), context)
    record_built(value, context)
  end

  defp record_stage(_arg_values, _value, _context), do: :ok

  defp record_used_queries(values, %{derived_value: _derived_value}) do
    stages = Process.get(@derived_stages_key)

    used_places =
      values
      |> queries_in()
      |> Enum.flat_map(&Map.get(stages.values, &1, []))

    Process.put(@derived_stages_key, %{
      stages
      | used: MapSet.union(stages.used, MapSet.new(used_places))
    })

    :ok
  end

  defp record_used_queries(_values, _context), do: :ok

  # A place that built a query no variant returned, and no stage or function of the project took,
  # sent its query somewhere else - into a value, or nowhere. The first such place in walk order is
  # refused.
  defp refuse_dropped_queries!(context) do
    %{places: places, used: used} = Process.get(@derived_stages_key)

    dropped =
      places
      |> Enum.reject(fn {key, _place} -> MapSet.member?(used, key) end)
      |> Enum.map(fn {_key, place} -> place end)
      |> Enum.min_by(& &1.order, fn -> nil end)

    if dropped do
      raise Hologram.CompileError,
        message: query_as_value_message(context.subject),
        file: dropped.file,
        line: dropped.line,
        stack: dropped.stack
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

  # Each variant is walked from the start, so the queries it holds start empty.
  defp reset_derived_stages(%{derived_value: _derived_value}) do
    Process.put(@derived_stages_key, %{Process.get(@derived_stages_key) | values: %{}})
  end

  defp reset_derived_stages(_context), do: :ok

  # A record becomes the queries it admits: over every entity type of the build when the entity
  # itself is unknown, over the one it already names when only an include name is.

  defp resolve(%SymbolicQuery{base: %Placeholder{}, stages: stages}, entity_types) do
    Enum.flat_map(entity_types, &replay(Enum.reverse(stages), &1))
  end

  defp resolve(%SymbolicQuery{base: base, stages: stages}, _entity_types) do
    replay(Enum.reverse(stages), base)
  end

  defp resolve(term, _entity_types), do: [term]

  defp scan_args_reach_query?(nodes, scope, entity_types, ir_plt, seen) do
    nodes
    |> Enum.map(&{&1, false})
    |> scan_reaches_query?(scope, entity_types, ir_plt, seen)
  end

  defp scan_node_reaches_query?(
         %IR.AtomType{value: value},
         tail?,
         _scope,
         entity_types,
         _ir_plt,
         seen
       ),
       do: {tail? and value in entity_types, seen}

  defp scan_node_reaches_query?(
         %IR.Block{expressions: expressions},
         tail?,
         scope,
         entity_types,
         ir_plt,
         seen
       ) do
    pairs = Enum.with_index(expressions, &{&1, tail? and &2 == length(expressions) - 1})

    scan_reaches_query?(pairs, scope, entity_types, ir_plt, seen)
  end

  defp scan_node_reaches_query?(
         %IR.Case{condition: condition, clauses: clauses},
         tail?,
         scope,
         entity_types,
         ir_plt,
         seen
       ) do
    pairs = [
      {condition, false}
      | Enum.flat_map(clauses, &[{&1.match, false}, {&1.guards, false}, {&1.body, tail?}])
    ]

    scan_reaches_query?(pairs, scope, entity_types, ir_plt, seen)
  end

  defp scan_node_reaches_query?(
         %IR.Cond{clauses: clauses},
         tail?,
         scope,
         entity_types,
         ir_plt,
         seen
       ) do
    pairs = Enum.flat_map(clauses, &[{&1.condition, false}, {&1.body, tail?}])

    scan_reaches_query?(pairs, scope, entity_types, ir_plt, seen)
  end

  defp scan_node_reaches_query?(
         %IR.LocalFunctionCall{function: function, args: args},
         tail?,
         scope,
         entity_types,
         ir_plt,
         seen
       ) do
    case reaches_query?({scope.module, function, length(args)}, tail?, entity_types, ir_plt, seen) do
      {true, next_seen} -> {true, next_seen}
      {false, next_seen} -> scan_args_reach_query?(args, scope, entity_types, ir_plt, next_seen)
    end
  end

  # A match evaluates to its right side.
  defp scan_node_reaches_query?(
         %IR.MatchOperator{left: left, right: right},
         tail?,
         scope,
         entity_types,
         ir_plt,
         seen
       ) do
    scan_reaches_query?([{left, false}, {right, tail?}], scope, entity_types, ir_plt, seen)
  end

  defp scan_node_reaches_query?(
         %IR.RemoteFunctionCall{
           module: %IR.AtomType{value: target},
           function: function,
           args: args
         },
         tail?,
         scope,
         entity_types,
         ir_plt,
         seen
       ) do
    cond do
      target in [Query, Stage] ->
        {true, seen}

      interpretable_module?(target) and not framework_module?(target) ->
        case reaches_query?({target, function, length(args)}, tail?, entity_types, ir_plt, seen) do
          {true, next_seen} ->
            {true, next_seen}

          {false, next_seen} ->
            scan_args_reach_query?(args, scope, entity_types, ir_plt, next_seen)
        end

      true ->
        scan_args_reach_query?(args, scope, entity_types, ir_plt, seen)
    end
  end

  defp scan_node_reaches_query?(
         %IR.Try{
           body: body,
           rescue_clauses: rescues,
           catch_clauses: catches,
           else_clauses: elses,
           after_block: after_block
         },
         tail?,
         scope,
         entity_types,
         ir_plt,
         seen
       ) do
    branches =
      Enum.map(rescues ++ catches ++ elses, &{&1, false}) ++
        Enum.map(rescues ++ catches ++ elses, &{&1.body, tail?})

    scan_reaches_query?(
      [{body, tail?}, {after_block, false} | branches],
      scope,
      entity_types,
      ir_plt,
      seen
    )
  end

  # A variable the field's result comes from holds what its bind's right side evaluates to. Each
  # bind is followed once per body: the scan stops at the first query it finds, so a bind followed
  # before found none, and following it again from another branch would only repeat the work.
  defp scan_node_reaches_query?(
         %IR.Variable{name: name, version: version},
         true,
         scope,
         entity_types,
         ir_plt,
         seen
       ) do
    followed = {:bind, scope.id, {name, version}}

    with false <- MapSet.member?(seen, followed),
         {:ok, bound} <- Map.fetch(scope.bindings, {name, version}) do
      scan_reaches_query?(
        [{bound, true}],
        scope,
        entity_types,
        ir_plt,
        MapSet.put(seen, followed)
      )
    else
      _skipped -> {false, seen}
    end
  end

  defp scan_node_reaches_query?(
         %IR.With{clauses: clauses, body: body, else_clauses: else_clauses},
         tail?,
         scope,
         entity_types,
         ir_plt,
         seen
       ) do
    pairs =
      [{clauses, false}, {body, tail?}] ++
        Enum.flat_map(
          else_clauses || [],
          &[{&1.match, false}, {&1.guards, false}, {&1.body, tail?}]
        )

    scan_reaches_query?(pairs, scope, entity_types, ir_plt, seen)
  end

  defp scan_node_reaches_query?(node, _tail?, scope, entity_types, ir_plt, seen)
       when is_struct(node) do
    node
    |> Map.from_struct()
    |> Map.values()
    |> scan_args_reach_query?(scope, entity_types, ir_plt, seen)
  end

  defp scan_node_reaches_query?(node, _tail?, scope, entity_types, ir_plt, seen)
       when is_list(node),
       do: scan_args_reach_query?(node, scope, entity_types, ir_plt, seen)

  defp scan_node_reaches_query?(node, _tail?, scope, entity_types, ir_plt, seen)
       when is_tuple(node) do
    node
    |> Tuple.to_list()
    |> scan_args_reach_query?(scope, entity_types, ir_plt, seen)
  end

  defp scan_node_reaches_query?(_node, _tail?, _scope, _entity_types, _ir_plt, seen),
    do: {false, seen}

  # Walks the given IR nodes, each with whether it stands where the field's result comes from, for
  # a query stage call, a call into the project reaching one, and an entity type in that position -
  # through a block's last expression, a branch's bodies, a call's callee and a variable's bind.
  defp scan_reaches_query?([], _scope, _entity_types, _ir_plt, seen), do: {false, seen}

  defp scan_reaches_query?([{node, tail?} | rest], scope, entity_types, ir_plt, seen) do
    case scan_node_reaches_query?(node, tail?, scope, entity_types, ir_plt, seen) do
      {true, next_seen} -> {true, next_seen}
      {false, next_seen} -> scan_reaches_query?(rest, scope, entity_types, ir_plt, next_seen)
    end
  end

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
  # A value only known at runtime has no spelling, since nothing computed it.
  defp spelled_value(%Placeholder{}), do: "a value only known at runtime"

  defp spelled_value(value), do: inspect(value)

  # An argument among the values gets a message of its own. The value it stands for arrives long
  # after the build, so what went wrong is that a query's SHAPE was asked to depend on it - and
  # naming the placeholder would show a compiler internal to someone who wrote a derived field.
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
  # There is always one: the derived field's own frame opens the stack before its body is walked.
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

  defp type_description([entity]), do: "a set of #{inspect(entity)} rows"

  defp type_description(:integer), do: "a count"

  defp type_description(entity), do: "one #{inspect(entity)} row"

  defp undefined_function_message(subject, module, function, arity) do
    "#{subject} calls undefined function #{inspect(module)}.#{function}/#{arity}"
  end

  defp unknown_value?(value), do: contains_placeholder?(value) or stand_in?(value)

  defp validate_derived_term!(term, entry, subject, module, line) do
    if not query_of_type?(term, entry.type) do
      raise_derived_type_mismatch!(term, entry, subject, module, line)
    end

    term
  end

  defp weaker(:match, outcome), do: outcome

  defp weaker(:unknown, _outcome), do: :unknown
end
