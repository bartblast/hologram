defmodule Hologram.Compiler.QueryChains do
  @moduledoc false

  # The queries browser code writes in one piece, read from the code the query macros compiled into
  # and checked when the app is built, so that a mistake in one fails the build at its line rather
  # than its page when it first renders.
  #
  # The macros turn query syntax into data at compile time: `Task |> filter(done == false) |>
  # include(project)` is `Stage.include(Stage.filter(Task, [done: {:==, false}]), [:project])` in the
  # IR. So a chain of stage calls whose innermost source is an entity module spelled out holds its
  # whole query as literals, but for the values pinned in it, which only exist at run time. A pinned
  # value stands in as a `Hologram.Query.Placeholder` wherever the stages take one - a compared value
  # or an operand, a membership list element, a filtered attribute's name, a sort key or direction,
  # a take, skip or page bound - and the stages check everything around it. Anything else that only
  # exists at run time, like a whole predicate list or include spec, ends the chain at that step:
  # the steps before it are checked, the rest is left to the check the query meets when it runs
  # (see `Hologram.Component.Derived.QueryCheck`). So whatever a stage refuses here is a real
  # mistake, never a stand-in in a place it can't be, and is shown in the stage's own words.
  #
  # A query assembled across variables, helpers or a reduce has no chain with a literal root, and is
  # left to the run-time check.

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.IR
  alias Hologram.Component.Derived.QueryCheck
  alias Hologram.Query.Placeholder
  alias Hologram.Query.Stage
  alias Hologram.Reflection

  @quantifiers [:all, :any, :none]

  @operators [
    :!=,
    :<,
    :<=,
    :==,
    :>,
    :>=,
    :contains,
    :contains_exact,
    :in,
    :not_in,
    :starts_with,
    :starts_with_exact
  ]

  # The query-building stages by name, with the arities they're called with. Hologram.Query
  # delegates its function stages to Hologram.Query.Stage, which the macros call.
  @stages %{
    count: [1],
    filter: [2, 3],
    include: [2, 3],
    one: [1],
    paginate: [2],
    skip: [2],
    sort: [2, 3],
    take: [2],
    trust: [1]
  }

  @stage_modules [Hologram.Query, Stage]

  @typedoc """
  One query written as a chain of stage calls: the function of the browser code it is written in,
  the entity module it starts from, each stage up to the first that holds something only known at
  run time other than a pinned value, with its arguments after the query and its line, whether its
  order is the one it is read in, and the line of its first call, which a chain cut before any step
  is told at.
  """
  @type t :: %{
          final_sort?: boolean,
          line: non_neg_integer | nil,
          mfa: mfa,
          root: module,
          steps: [{atom, list, non_neg_integer | nil}]
        }

  @doc """
  Returns the query chains the given function clauses write, outermost first.
  """
  @spec collect([IR.FunctionClause.t()], mfa) :: [t]
  def collect(clauses, mfa) do
    clauses
    |> Enum.reduce([], &walk_clause(&1, mfa, &2))
    |> Enum.reverse()
  end

  @doc """
  Raises Hologram.CompileError when the given chain is a query no browser may run: one a stage
  refuses, in the stage's own words, or one `Hologram.Component.Derived.QueryCheck` refuses - over a
  type no rule lets anyone read, filtering or sorting on a server-only attribute, or claiming trust.
  It is located at the call that refused, in the file of the module the chain is written in: a
  check's refusal at the first stage whose query it refuses the same way. A chain whose root is no
  entity type is a call of some other code, and passes.

  Its order is checked only where nothing can sort the query again, or count it, which drops the
  order: a derived field's own query, or one handed straight to `Hologram.DB`, with no stage after
  the cut that could. Anywhere else, like a query a variable or a helper hands on, a sort on a
  server-only attribute isn't refused here.
  """
  @spec validate!(t, PLT.t() | nil) :: :ok
  def validate!(%{root: root} = chain, module_info_plt) do
    if Reflection.entity?(root, module_info_plt) do
      prefixes = built_prefixes(chain)
      {term, last_line} = List.last(prefixes)

      # The whole query decides, since a later stage can drop what an earlier one asked for, like a
      # sort replaced by another. The stage it is told at is the first whose query is refused the
      # same way.
      if refusal = refusal(term, chain.final_sort?) do
        line = refusal_line(prefixes, refusal, chain.final_sort?, last_line)
        raise_compile_error!(chain.mfa, line, "#{subject(chain.mfa)} #{refusal}")
      end
    end

    :ok
  end

  defp apply_stage!(function, args, mfa, line) do
    apply(Stage, function, args)
  rescue
    error in Hologram.MisuseError ->
      raise_compile_error!(
        mfa,
        line,
        "#{subject(mfa)} builds an invalid query - #{Exception.message(error)}"
      )
  end

  # The query each stage of the chain has built so far, normalized, with the line of that stage -
  # the root alone, at the chain's line, first. A stage's refusal raises here, at its line.
  defp built_prefixes(%{line: chain_line, mfa: mfa, root: root, steps: steps}) do
    root_term = apply_stage!(:normalize, [root], mfa, chain_line)

    {prefixes, _query} =
      Enum.map_reduce(steps, root, fn {function, args, line}, query ->
        built = apply_stage!(function, [query | args], mfa, line)
        {{apply_stage!(:normalize, [built], mfa, line), line}, built}
      end)

    [{root_term, chain_line} | prefixes]
  end

  defp refusal_line(prefixes, refusal, final_sort?, last_line) do
    Enum.find_value(prefixes, last_line, fn {prefix, line} ->
      if refusal(prefix, final_sort?) == refusal, do: line
    end)
  end

  defp refusal(term, true = _final_sort?), do: QueryCheck.refusal(term)

  defp refusal(term, false = _final_sort?), do: QueryCheck.refusal(%{term | sort: []})

  # The steps of a chain, innermost first: each stage call's arguments after the query, as terms,
  # up to the first call holding something a stand-in can't take.
  defp chain_steps(calls) do
    steps =
      Enum.reduce_while(calls, [], fn call, steps ->
        [_query | args] = call.args

        case step_args(call.function, args) do
          {:ok, terms} -> {:cont, [{call.function, terms, call.line} | steps]}
          :cut -> {:halt, steps}
        end
      end)

    {Enum.reverse(steps), Enum.drop(calls, length(steps))}
  end

  # Alternatives are told by their shape, as the stages tell them: a list of lists. Any other list
  # is a membership in an attribute of the same name.
  defp entry(%IR.TupleType{
         data: [%IR.AtomType{value: :or}, %IR.ListType{data: alternatives} = value]
       }) do
    if Enum.all?(alternatives, &is_struct(&1, IR.ListType)) do
      {:or, Enum.map(alternatives, &predicates!/1)}
    else
      comparison_entry(:or, value)
    end
  end

  # A quantifier is told by its shape, as the stages tell it (see quantifier_value?/1 in
  # Hologram.Query.Stage): a source - a list of relationships, or one read on a row above - and a
  # list of predicates. Any other value is a comparison of an attribute of the same name.
  defp entry(%IR.TupleType{
         data: [
           %IR.AtomType{value: quantifier},
           %IR.TupleType{data: [source, %IR.ListType{} = predicates]}
         ]
       })
       when quantifier in @quantifiers and
              (is_struct(source, IR.ListType) or
                 (is_struct(source, IR.TupleType) and length(source.data) == 3 and
                    is_struct(hd(source.data), IR.AtomType) and
                    hd(source.data).value == :outer)) do
    {quantifier, {literal!(source), predicates!(predicates)}}
  end

  # An alternative or a quantifier whose value only the run knows has a shape the build can't read -
  # a list of alternatives, a source with its condition - so a stand-in can't take its place. An
  # attribute of the same name compared with a literal or through an operator is read as any
  # attribute's comparison is.
  defp entry(%IR.TupleType{data: [%IR.AtomType{value: name}, value]})
       when name == :or or name in @quantifiers do
    comparison_entry(name, value)
  end

  defp entry(%IR.TupleType{data: [name, value]}) do
    name_term =
      case literal(name) do
        {:ok, term} -> term
        :error -> placeholder(name)
      end

    {name_term, value(value)}
  end

  defp entry(_ir), do: throw(:cut)

  defp comparison_entry(name, value) do
    if literal(value) == :error and not operator_value_ir?(value) do
      throw(:cut)
    else
      {name, value(value)}
    end
  end

  # A literal IR node as the term it spells, or :error for one only known at run time.
  defp literal(%IR.AtomType{value: value}), do: {:ok, value}

  defp literal(%IR.FloatType{value: value}), do: {:ok, value}

  defp literal(%IR.IntegerType{value: value}), do: {:ok, value}

  defp literal(%IR.StringType{value: value}), do: {:ok, value}

  defp literal(%IR.ListType{data: data}), do: literals(data, &Function.identity/1)

  defp literal(%IR.TupleType{data: data}), do: literals(data, &List.to_tuple/1)

  defp literal(%IR.MapType{data: pairs}) do
    pairs
    |> Enum.flat_map(fn {key, value} -> [key, value] end)
    |> literals(fn terms ->
      terms
      |> Enum.chunk_every(2)
      |> Map.new(fn [key, value] -> {key, value} end)
    end)
  end

  # A struct literal a value is written as, like a range, compiles to a call of its module's
  # __struct__/1 with the fields.
  defp literal(%IR.RemoteFunctionCall{
         module: %IR.AtomType{value: module},
         function: :__struct__,
         args: [fields]
       }) do
    with {:ok, pairs} <- literal(fields),
         true <- Keyword.keyword?(pairs) do
      {:ok, struct!(module, pairs)}
    else
      _not_literal -> :error
    end
  rescue
    _error -> :error
  end

  defp literal(_ir), do: :error

  defp literal!(ir) do
    case literal(ir) do
      {:ok, term} -> term
      :error -> throw(:cut)
    end
  end

  defp literals(irs, build) do
    collected =
      Enum.reduce_while(irs, {:ok, []}, fn ir, {:ok, acc} ->
        case literal(ir) do
          {:ok, term} -> {:cont, {:ok, [term | acc]}}
          :error -> {:halt, :error}
        end
      end)

    case collected do
      {:ok, reversed_terms} ->
        terms = Enum.reverse(reversed_terms)
        {:ok, build.(terms)}

      :error ->
        :error
    end
  end

  # A stand-in for what only the run knows, named after the variable it reads when it is one.
  defp placeholder(%IR.Variable{name: name}), do: %Placeholder{name: name}

  defp placeholder(_ir), do: %Placeholder{name: :pinned}

  defp predicates!(%IR.ListType{data: entries}), do: Enum.map(entries, &entry/1)

  defp predicates!(_ir), do: throw(:cut)

  defp raise_compile_error!({module, _function, _arity}, line, message) do
    raise Hologram.CompileError,
      message: message,
      file: Reflection.source_path(module),
      line: line
  end

  # The calls of a chain from its innermost outwards, and its root - what the innermost call's query
  # is.
  defp unwind(%IR.RemoteFunctionCall{args: [query | _args]} = call, calls) do
    if stage_call?(query), do: unwind(query, [call | calls]), else: {query, [call | calls]}
  end

  defp sort_entry(%IR.AtomType{value: key}), do: key

  defp sort_entry(%IR.TupleType{data: [key, direction]}) do
    {value_or_placeholder(key), value_or_placeholder(direction)}
  end

  defp sort_entry(ir), do: value_or_placeholder(ir)

  defp stage_call?(%IR.RemoteFunctionCall{
         module: %IR.AtomType{value: module},
         function: function,
         args: args
       })
       when module in @stage_modules do
    length(args) in Map.get(@stages, function, [])
  end

  defp stage_call?(_ir), do: false

  defp step_args(function, args) do
    {:ok, step_terms(function, args)}
  catch
    :cut -> :cut
  end

  defp step_terms(:filter, [predicates | hints]), do: [predicates!(predicates) | literals!(hints)]

  defp step_terms(:sort, [%IR.AtomType{value: key} | hints]), do: [key | literals!(hints)]

  defp step_terms(:sort, [%IR.ListType{data: entries} | hints]) do
    [Enum.map(entries, &sort_entry/1) | literals!(hints)]
  end

  defp step_terms(:sort, [spec | hints]), do: [value_or_placeholder(spec) | literals!(hints)]

  defp step_terms(:paginate, [%IR.ListType{data: options}]) do
    [
      Enum.map(options, fn
        %IR.TupleType{data: [%IR.AtomType{value: name}, value]} ->
          {name, value_or_placeholder(value)}

        _option ->
          throw(:cut)
      end)
    ]
  end

  defp step_terms(function, [bound]) when function in [:skip, :take] do
    [value_or_placeholder(bound)]
  end

  defp step_terms(_function, args), do: literals!(args)

  defp literals!(irs), do: Enum.map(irs, &literal!/1)

  # A filter's value: a literal, an operator with its operand, a membership list of literals and
  # stand-ins, or a stand-in for one only the run knows.
  # Any pair starting with an atom is an operator tuple to the stages, which refuse an unknown one,
  # except an attribute reference.
  defp value(%IR.TupleType{data: [%IR.AtomType{value: operator}, operand]})
       when operator != :attribute do
    {operator, value(operand)}
  end

  # A list mixing operators with stand-ins is one stand-in: a stand-in there may be an operator or a
  # plain value, and the stages take a list of only one kind.
  defp value(%IR.ListType{data: elements} = ir) do
    case literal(ir) do
      {:ok, term} -> term
      :error -> list_value(Enum.map(elements, &value/1), ir)
    end
  end

  defp value(ir), do: value_or_placeholder(ir)

  defp list_value(values, ir) do
    if Enum.any?(values, &operator_value?/1) and Enum.any?(values, &is_struct(&1, Placeholder)) do
      placeholder(ir)
    else
      values
    end
  end

  defp operator_value_ir?(%IR.TupleType{data: [%IR.AtomType{value: operator}, _operand]}),
    do: operator in @operators

  defp operator_value_ir?(_ir), do: false

  defp operator_value?({operator, _operand}) when operator in @operators, do: true

  defp operator_value?(_value), do: false

  defp value_or_placeholder(ir) do
    case literal(ir) do
      {:ok, term} -> term
      :error -> placeholder(ir)
    end
  end

  # A component's or a page's derived field is spelled by its name, the function its body is hoisted
  # into an implementation detail.
  defp subject({module, function, _arity} = mfa) do
    case Atom.to_string(function) do
      "__derived_" <> rest when rest != "_" ->
        name = String.trim_trailing(rest, "__")
        "derived field :#{name} in #{Reflection.module_name(module)}"

      _name ->
        "the query in #{Exception.format_mfa(module, elem(mfa, 1), elem(mfa, 2))}"
    end
  end

  defp walk(
         %IR.RemoteFunctionCall{module: %IR.AtomType{value: Hologram.DB}, args: args},
         mfa,
         acc
       ) do
    Enum.reduce(args, acc, &walk_value(&1, mfa, &2, true))
  end

  defp walk(%IR.RemoteFunctionCall{} = call, mfa, acc) do
    if stage_call?(call) do
      walk_query(call, mfa, acc, false)
    else
      call
      |> Map.from_struct()
      |> Map.values()
      |> walk(mfa, acc)
    end
  end

  defp walk(list, mfa, acc) when is_list(list), do: Enum.reduce(list, acc, &walk(&1, mfa, &2))

  defp walk(map, mfa, acc) when is_map(map) do
    map
    |> Map.values()
    |> walk(mfa, acc)
  end

  defp walk(tuple, mfa, acc) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> walk(mfa, acc)
  end

  defp walk(_ir, _mfa, acc), do: acc

  # A derived field's body is the query the field reads, so the chain it ends with is read as is.
  defp walk_clause(
         %IR.FunctionClause{body: %IR.Block{expressions: expressions}} = clause,
         mfa,
         acc
       )
       when expressions != [] do
    acc = walk([clause.params, clause.guards], mfa, acc)

    walk_tail(expressions, mfa, acc, derived_body?(mfa))
  end

  defp walk_clause(clause, mfa, acc), do: walk(clause, mfa, acc)

  # A block's value is its last expression's: a derived field's body of several expressions is a
  # block inside the clause's own.
  defp walk_tail(expressions, mfa, acc, read_as_is?) do
    {init, [tail]} = Enum.split(expressions, -1)

    walk_value(tail, mfa, walk(init, mfa, acc), read_as_is?)
  end

  # A value, read as is when nothing can sort it again once it is built. A block's, case's, cond's,
  # with's or try's is the value of the expression or clause body it ends with - an if, unless, &&
  # and || are cases here - while what picks the clause is a value like any other. A try with else
  # clauses hands its body's value to them, and its after block's value is never the try's.
  defp walk_value(
         %IR.Block{expressions: [_expression | _expressions] = expressions},
         mfa,
         acc,
         read_as_is?
       ) do
    walk_tail(expressions, mfa, acc, read_as_is?)
  end

  defp walk_value(%IR.Case{condition: condition, clauses: clauses}, mfa, acc, read_as_is?) do
    walk_clauses(clauses, mfa, walk(condition, mfa, acc), read_as_is?)
  end

  defp walk_value(%IR.Cond{clauses: clauses}, mfa, acc, read_as_is?) do
    Enum.reduce(clauses, acc, fn clause, clause_acc ->
      walk_value(clause.body, mfa, walk(clause.condition, mfa, clause_acc), read_as_is?)
    end)
  end

  defp walk_value(%IR.With{} = with_ir, mfa, acc, read_as_is?) do
    body_acc = walk_value(with_ir.body, mfa, walk(with_ir.clauses, mfa, acc), read_as_is?)

    walk_clauses(with_ir.else_clauses, mfa, body_acc, read_as_is?)
  end

  defp walk_value(%IR.Try{} = try_ir, mfa, acc, read_as_is?) do
    after_acc = walk(try_ir.after_block, mfa, acc)

    body_acc =
      if try_ir.else_clauses == [] do
        walk_value(try_ir.body, mfa, after_acc, read_as_is?)
      else
        walk_clauses(try_ir.else_clauses, mfa, walk(try_ir.body, mfa, after_acc), read_as_is?)
      end

    catch_acc = walk_clauses(try_ir.catch_clauses, mfa, body_acc, read_as_is?)

    Enum.reduce(try_ir.rescue_clauses, catch_acc, &walk_value(&1.body, mfa, &2, read_as_is?))
  end

  # A match's value is its right-hand side's.
  defp walk_value(%IR.MatchOperator{left: left, right: right}, mfa, acc, read_as_is?) do
    walk_value(right, mfa, walk(left, mfa, acc), read_as_is?)
  end

  defp walk_value(ir, mfa, acc, read_as_is?), do: walk_query(ir, mfa, acc, read_as_is?)

  # The clauses of a case, a with's or a try's else or a try's catch: what each matches against is
  # a value like any other, and its body is the value.
  defp walk_clauses(clauses, mfa, acc, read_as_is?) do
    Enum.reduce(clauses, acc, fn clause, clause_acc ->
      clause_acc =
        clause
        |> Map.from_struct()
        |> Map.delete(:body)
        |> Map.values()
        |> walk(mfa, clause_acc)

      walk_value(clause.body, mfa, clause_acc, read_as_is?)
    end)
  end

  defp derived_body?({_module, function, _arity}) do
    case Atom.to_string(function) do
      "__derived_" <> rest -> rest != "_"
      _name -> false
    end
  end

  # A query, read as is when nothing can sort it again once it is built.
  defp walk_query(ir, mfa, acc, read_as_is?) do
    if stage_call?(ir) do
      {root, calls} = unwind(ir, [])

      acc =
        case root do
          %IR.AtomType{value: module} when is_atom(module) and module not in [nil, true, false] ->
            {steps, unread_calls} = chain_steps(calls)
            reorders? = Enum.any?(unread_calls, &(&1.function in [:count, :sort]))

            chain = %{
              final_sort?: read_as_is? and not reorders?,
              line: hd(calls).line,
              mfa: mfa,
              root: module,
              steps: steps
            }

            [chain | acc]

          # A chain built on a case's or a block's value reads that value as the chain does, unless
          # a stage of the chain can sort it again.
          _root ->
            reorders? = Enum.any?(calls, &(&1.function in [:count, :sort]))
            walk_value(root, mfa, acc, read_as_is? and not reorders?)
        end

      Enum.reduce(calls, acc, fn %{args: [_query | args]}, inner_acc ->
        walk(args, mfa, inner_acc)
      end)
    else
      walk(ir, mfa, acc)
    end
  end
end
