defmodule Hologram.Compiler.DataFlow do
  @moduledoc false

  # Follows values through server code without running it, to tell which struct types and module
  # atoms can be inside the value an expression gives or a function returns. The compiler asks it
  # about the values init/3 and command/3 hand to the client, so that a type built on the server and
  # dropped there ships none of its protocol implementations.
  #
  # A value is described by shapes (see shape/0): a set of alternatives, each saying what kind of
  # value it is and what can be inside it. What is inside a list, a map or a struct is kept flat,
  # since only the types somewhere inside matter; a tuple keeps its elements apart, so that an
  # `{:ok, value}` pattern takes the value and leaves the error alternatives out.
  #
  # The contract every rule keeps: the answer is never smaller than the compiler's rule before this
  # module, for the same code.
  #
  #   1. What the analysis cannot follow stands for that rule applied from where it stopped:
  #      `{:reach, vertex}` is any struct created and any component named in the code the call graph
  #      reaches from the vertex. A function it gives up on returns its top (see top/1).
  #   2. Branches merge by union. Guards are ignored: they can only rule values out.
  #   3. An Erlang function has no IR. One without a hand-written answer returns everything in its
  #      arguments: it cannot build an Elixir struct, only pass one on.
  #   4. A protocol call returns everything in its arguments, unless it has a hand-written answer.
  #   5. A call on a module the code does not name returns everything in its arguments and in the
  #      module, and the answers of the functions it can call when the module is known.
  #   6. A value from outside the code (a session, a stash, a database row, a message) holds only
  #      the types the code names for it, as before this module: a variable matched against a
  #      pattern that names a module or a struct holds what the pattern names.

  alias Hologram.Commons.PLT
  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.IR

  # How many summaries can be in the making at once, one inside another. A call past it gives the
  # callee's top.
  @max_call_depth 64

  # Shapes of unknown structure: they can hold anything, so they can match any pattern, and a part
  # of one is the shape itself.
  @opaque_kinds [:arg, :bag, :call, :dyn, :param, :reach]

  @primitive_types [
    IR.BitstringType,
    IR.FloatType,
    IR.IntegerType,
    IR.PIDType,
    IR.PortType,
    IR.ReferenceType,
    IR.Stacktrace,
    IR.StringType
  ]

  # One alternative of a value:
  #
  #   * `{:atom, atom}` - the atom, a module atom included.
  #   * `:prim` - a number, a binary, a pid, a port or a reference: nothing inside.
  #   * `{:struct, module, shapes}` - a struct of the module, with what is in its fields.
  #   * `{:map, shapes}` - a map, with its keys and values.
  #   * `{:tuple, [shapes]}` - a tuple, with its elements in order.
  #   * `{:list, shapes}` - a list, with its elements.
  #   * `{:bag, shapes}` - a value of unknown structure holding the shapes.
  #   * `{:fun, reference, shapes}` - an anonymous function and what it returns, in terms of its
  #     own arguments.
  #   * `{:param, index}` - whatever the function being summarised is given as that argument.
  #   * `{:arg, reference, index}` - whatever the anonymous function is given as that argument.
  #   * `{:reach, vertex}` - the rule before this module, applied from the vertex (see the contract).
  #   * `{:call, shapes, [shapes]}` - a call of a function value that depends on a parameter.
  #   * `{:dyn, shapes, name, arity, [shapes]}` - a call of the named function on a module that
  #     depends on a parameter.
  @type shape ::
          {:atom, atom}
          | :prim
          | {:struct, module, shapes}
          | {:map, shapes}
          | {:tuple, [shapes]}
          | {:list, shapes}
          | {:bag, shapes}
          | {:fun, reference, shapes}
          | {:param, non_neg_integer}
          | {:arg, reference, non_neg_integer}
          | {:reach, CallGraph.vertex()}
          | {:call, shapes, [shapes]}
          | {:dyn, shapes, atom, arity, [shapes]}

  @type shapes :: MapSet.t(shape)

  # What a compile's analysis works with: the IR PLT the code is read from (and where missing IR is
  # built), the module info PLT, and the summaries of the functions it has followed so far.
  @type t :: %{ir_plt: PLT.t(), module_info_plt: PLT.t(), summaries: PLT.t()}

  # The types shapes hold (see types/2).
  @type types :: %{
          modules: MapSet.t(module),
          reach: MapSet.t(CallGraph.vertex()),
          structs: MapSet.t(module)
        }

  @doc """
  Returns the shapes a summary (see `summary/2`) gives for a call with arguments of the given
  shapes: each `{:param, index}` in it, at any depth, replaced with the argument's shapes. A missing
  argument gives nothing.
  """
  @spec apply_summary(shapes, [shapes]) :: shapes
  def apply_summary(summary, args) do
    summary
    |> Enum.map(&substitute(&1, args))
    |> union()
  end

  @doc """
  Returns the shapes of the value the given expression gives, where the expression is in the given
  clause of the given function: a variable holds what its binding in the clause gives, and a
  parameter of the clause is `{:param, index}`.
  """
  @spec shapes(IR.t(), IR.FunctionClause.t(), mfa, t) :: shapes
  def shapes(expr, clause, mfa, flow) do
    run(fn memo ->
      ctx = %{flow: flow, frames: [clause_frame(clause)], memo: memo, mfa: mfa, stack: [mfa]}
      eval(expr, ctx)
    end)
  end

  @doc """
  Starts the analysis of a compile, which reads IR from the given IR PLT and module facts from the
  given module info PLT.
  """
  @spec start(PLT.t(), PLT.t()) :: t
  def start(ir_plt, module_info_plt) do
    %{ir_plt: ir_plt, module_info_plt: module_info_plt, summaries: PLT.start()}
  end

  @doc """
  Stops the given analysis.
  """
  @spec stop(t) :: :ok
  def stop(%{summaries: summaries}), do: PLT.stop(summaries)

  @doc """
  Returns the summary of the given function: the shapes of the value it returns, in terms of its
  parameters (`{:param, index}`), the union over its clauses. A function with no IR (one of an
  Erlang module, or of a module with no beam) or that its module doesn't define returns everything
  it is given. A summary is kept in the analysis once made, for the rest of the compile.

  A call of a function whose summary is still being made (recursion) gives the callee's top, for
  now, and so does a call made with too many summaries in the making, one inside another.
  """
  @spec summary(mfa, t) :: shapes
  def summary(mfa, flow) do
    run(fn memo ->
      callee_summary(mfa, %{flow: flow, frames: [], memo: memo, mfa: mfa, stack: []})
    end)
  end

  @doc """
  Returns what the given function's value is when the analysis cannot follow it: the rule before
  this module applied from the function, and everything the function is given.
  """
  @spec top(mfa) :: shapes
  def top({_module, _function, arity} = mfa) do
    arity
    |> params()
    |> MapSet.put({:reach, mfa})
  end

  @doc """
  Returns the types the given shapes hold, at any depth:

    * `:structs` - the modules of the structs, and the module atoms of struct modules.
    * `:modules` - the module atoms the module info PLT knows.
    * `:reach` - the vertices the rule before this module applies from (see `top/1`).

  A param or an anonymous function's argument holds nothing: the value the shapes are asked about
  is one no caller gives anything to. An anonymous function holds what it returns, and a call the
  analysis could not make holds its function or module and its arguments.
  """
  @spec types(shapes, t) :: types
  def types(shapes, flow) do
    acc = %{modules: MapSet.new(), reach: MapSet.new(), structs: MapSet.new()}
    put_types(shapes, acc, flow.module_info_plt)
  end

  # Records that every variable of the pattern is bound by matching the pattern against the subject
  # (see subject_shapes/2), and what the pattern names for the variables matched against a part of it.
  defp bind_pattern(acc, pattern, subject) do
    new_acc =
      pattern
      |> pattern_variables([])
      |> Enum.reduce(acc, &put_binding(&2, &1, {pattern, subject}))

    put_pattern_extras(new_acc, pattern)
  end

  # The summary of a function a call reaches, from the analysis when made already.
  defp callee_summary(mfa, ctx) do
    if mfa in ctx.stack or length(ctx.stack) >= @max_call_depth do
      top(mfa)
    else
      case PLT.get(ctx.flow.summaries, mfa) do
        {:ok, summary} ->
          summary

        :error ->
          summary = function_summary(mfa, ctx)
          PLT.put(ctx.flow.summaries, mfa, summary)
          summary
      end
    end
  end

  # The variables of a function clause (or, later, of an anonymous function's clause), each with the
  # places it is bound at and the shapes the patterns it is matched against name for it. A variable
  # of IR read from a BEAM has a version per binding, so a variable is a name and a version.
  defp clause_frame(%IR.FunctionClause{params: params, guards: guards, body: body}) do
    acc =
      params
      |> Enum.with_index()
      |> Enum.reduce(%{bindings: %{}, extras: %{}}, fn {param, index}, acc ->
        bind_pattern(acc, param, {:param, index})
      end)

    [guards, body]
    |> index(acc)
    |> Map.put(:id, make_ref())
  end

  # What can be inside a value of the given shapes, one level down. An atom and a primitive hold
  # nothing; a shape of unknown structure holds itself.
  defp contents(shapes) do
    shapes
    |> Enum.map(&shape_contents/1)
    |> union()
  end

  defp eval(%IR.AtomType{value: value}, _ctx), do: MapSet.new([{:atom, value}])

  defp eval(%IR.Block{expressions: []}, _ctx), do: MapSet.new([{:atom, nil}])

  defp eval(%IR.Block{expressions: expressions}, ctx) do
    expressions
    |> List.last()
    |> eval(ctx)
  end

  defp eval(%IR.Case{clauses: clauses}, ctx) do
    clauses
    |> Enum.map(& &1.body)
    |> eval_all(ctx)
  end

  defp eval(%IR.Comprehension{reducer: nil, collectable: collectable, mapper: mapper}, ctx) do
    mapped = eval(mapper, ctx)

    case collectable do
      %IR.ListType{data: []} ->
        MapSet.new([{:list, mapped}])

      %IR.MapType{data: []} ->
        MapSet.new([{:map, contents(mapped)}])

      _other ->
        inner =
          collectable
          |> eval(ctx)
          |> MapSet.union(mapped)

        MapSet.new([{:bag, inner}])
    end
  end

  defp eval(%IR.Comprehension{reducer: %{initial_value: initial_value, clauses: clauses}}, ctx) do
    inner = eval_all([initial_value | Enum.map(clauses, & &1.body)], ctx)
    MapSet.new([{:bag, inner}])
  end

  defp eval(%IR.Cond{clauses: clauses}, ctx) do
    clauses
    |> Enum.map(& &1.body)
    |> eval_all(ctx)
  end

  defp eval(%IR.ConsOperator{head: head, tail: tail}, ctx) do
    elements =
      tail
      |> eval(ctx)
      |> contents()
      |> MapSet.union(eval(head, ctx))

    MapSet.new([{:list, elements}])
  end

  defp eval(%IR.ListType{data: data}, ctx) do
    MapSet.new([{:list, eval_all(data, ctx)}])
  end

  defp eval(%IR.LocalFunctionCall{function: function, args: args}, ctx) do
    {module, _function, _arity} = ctx.mfa
    eval_call({module, function, length(args)}, args, ctx)
  end

  defp eval(%IR.MapType{data: data}, ctx) do
    MapSet.new([map_shape(data, &eval(&1, ctx))])
  end

  # The value of a match is its right side.
  defp eval(%IR.MatchOperator{right: right}, ctx), do: eval(right, ctx)

  # A struct literal outside a pattern: `%Mod{a: 1}` is `Mod.__struct__([a: 1])` in IR, with the
  # default fields filled in.
  defp eval(
         %IR.RemoteFunctionCall{
           module: %IR.AtomType{value: module},
           function: :__struct__,
           args: args
         },
         ctx
       )
       when length(args) in [0, 1] do
    fields =
      args
      |> Enum.map(&struct_fields(&1, ctx))
      |> union()

    MapSet.new([{:struct, module, fields}])
  end

  defp eval(
         %IR.RemoteFunctionCall{
           module: %IR.AtomType{value: module},
           function: function,
           args: args
         },
         ctx
       ) do
    eval_call({module, function, length(args)}, args, ctx)
  end

  # With else clauses, the body's value goes through them; a rescue or a catch gives its own.
  defp eval(%IR.Try{} = ir, ctx) do
    value_bodies =
      if ir.else_clauses == [] do
        [ir.body]
      else
        Enum.map(ir.else_clauses, & &1.body)
      end

    handler_bodies = Enum.map(ir.rescue_clauses ++ ir.catch_clauses, & &1.body)

    eval_all(value_bodies ++ handler_bodies, ctx)
  end

  defp eval(%IR.TupleType{data: data}, ctx) do
    MapSet.new([{:tuple, Enum.map(data, &eval(&1, ctx))}])
  end

  # A variable of IR built from a code string has no version, so its bindings can't be told apart.
  defp eval(%IR.Variable{version: nil}, ctx), do: top(ctx.mfa)

  defp eval(%IR.Variable{name: name, version: version}, ctx) do
    read_variable({name, version}, ctx)
  end

  # Without else clauses, a value a clause does not match is the with's value.
  defp eval(%IR.With{clauses: clauses, body: body, else_clauses: []}, ctx) do
    unmatched_exprs = for %IR.WithMatchClause{expression: expr} <- clauses, do: expr
    eval_all([body | unmatched_exprs], ctx)
  end

  defp eval(%IR.With{body: body, else_clauses: else_clauses}, ctx) do
    eval_all([body | Enum.map(else_clauses, & &1.body)], ctx)
  end

  defp eval(%type{}, _ctx) when type in @primitive_types, do: MapSet.new([:prim])

  defp eval(_expr, ctx), do: top(ctx.mfa)

  defp eval_all(exprs, ctx) do
    exprs
    |> Enum.map(&eval(&1, ctx))
    |> union()
  end

  # The callee's summary with the arguments put in. An argument the summary doesn't hold is not
  # followed: whatever it holds can't reach the call's value.
  defp eval_call(mfa, args, ctx) do
    summary = callee_summary(mfa, ctx)
    used_indexes = param_indexes(summary, MapSet.new())

    arg_shapes =
      args
      |> Enum.with_index()
      |> Enum.map(fn {arg, index} ->
        if MapSet.member?(used_indexes, index), do: eval(arg, ctx), else: MapSet.new()
      end)

    apply_summary(summary, arg_shapes)
  end

  # The part of a value of the given shapes that the pattern binds to the variable, from the
  # alternatives the pattern can match.
  defp extract(shapes, pattern, var) do
    shapes
    |> Enum.filter(&may_match?(&1, pattern))
    |> Enum.map(&extract_shape(&1, pattern, var))
    |> union()
  end

  defp extract_shape(shape, %IR.Variable{name: name, version: version}, {name, version}) do
    MapSet.new([shape])
  end

  defp extract_shape(shape, %IR.MatchOperator{left: left, right: right}, var) do
    union([extract_shape(shape, left, var), extract_shape(shape, right, var)])
  end

  # A variable in a binary pattern takes a binary or a number.
  defp extract_shape(_shape, %IR.BitstringType{} = pattern, var) do
    if var in pattern_variables(pattern, []), do: MapSet.new([:prim]), else: MapSet.new()
  end

  defp extract_shape({:tuple, elements}, %IR.TupleType{data: patterns}, var) do
    elements
    |> Enum.zip(patterns)
    |> Enum.map(fn {element, pattern} -> extract(element, pattern, var) end)
    |> union()
  end

  defp extract_shape({:list, elements}, %IR.ListType{data: patterns}, var) do
    patterns
    |> Enum.map(&extract(elements, &1, var))
    |> union()
  end

  defp extract_shape({:list, elements} = shape, %IR.ConsOperator{head: head, tail: tail}, var) do
    union([extract(elements, head, var), extract(MapSet.new([shape]), tail, var)])
  end

  defp extract_shape({:struct, module, fields}, %IR.MapType{data: pairs}, var) do
    pairs
    |> Enum.map(fn
      {%IR.AtomType{value: :__struct__}, value} ->
        extract(MapSet.new([{:atom, module}]), value, var)

      {key, value} ->
        union([extract(fields, key, var), extract(fields, value, var)])
    end)
    |> union()
  end

  defp extract_shape({:map, inner}, %IR.MapType{data: pairs}, var) do
    pairs
    |> Enum.map(fn {key, value} ->
      union([extract(inner, key, var), extract(inner, value, var)])
    end)
    |> union()
  end

  defp extract_shape(shape, pattern, var) do
    if opaque?(shape) and var in pattern_variables(pattern, []) do
      MapSet.new([shape])
    else
      MapSet.new()
    end
  end

  defp function_clauses({module, function, arity}, ctx) do
    module
    |> module_functions(ctx)
    |> Map.get({function, arity})
  end

  defp function_summary({_module, _function, arity} = mfa, ctx) do
    case function_clauses(mfa, ctx) do
      nil ->
        MapSet.new([{:bag, params(arity)}])

      clauses ->
        function_ctx = %{ctx | mfa: mfa, stack: [mfa | ctx.stack]}

        clauses
        |> Enum.map(&eval(&1.body, %{function_ctx | frames: [clause_frame(&1)]}))
        |> union()
    end
  end

  # Collects the bindings of the variables in the given IR (see clause_frame/1). The places a
  # variable is bound at: a match, a case clause, a with clause and its else clauses, a comprehension
  # generator and its reducer, a rescue, a catch and a try's else clauses. An anonymous function's
  # clauses bind variables of their own, which it doesn't collect.
  defp index(%IR.AnonymousFunctionType{}, acc), do: acc

  defp index(%IR.Case{condition: condition, clauses: clauses}, acc) do
    Enum.reduce(
      clauses,
      index(condition, acc),
      &index_clause(&1, {:expr, condition}, condition, &2)
    )
  end

  defp index(%IR.Comprehension{} = ir, acc) do
    qualifiers_acc = Enum.reduce(ir.qualifiers, acc, &index_qualifier/2)
    new_acc = index([ir.collectable, ir.mapper], qualifiers_acc)

    case ir.reducer do
      nil ->
        new_acc

      %{initial_value: initial_value, clauses: clauses} ->
        Enum.reduce(clauses, index(initial_value, new_acc), &index_clause(&1, :top, nil, &2))
    end
  end

  defp index(%IR.MatchOperator{left: left, right: right}, acc) do
    new_acc =
      acc
      |> bind_pattern(left, {:expr, right})
      |> put_subject_extras(right, left)

    index(right, new_acc)
  end

  defp index(%IR.Try{} = ir, acc) do
    body_acc = index(ir.body, acc)
    rescue_acc = Enum.reduce(ir.rescue_clauses, body_acc, &index_rescue/2)
    catch_acc = Enum.reduce(ir.catch_clauses, rescue_acc, &index_catch/2)

    else_acc =
      Enum.reduce(ir.else_clauses, catch_acc, &index_clause(&1, {:expr, ir.body}, nil, &2))

    index(ir.after_block, else_acc)
  end

  defp index(%IR.With{clauses: clauses, body: body, else_clauses: else_clauses}, acc) do
    unmatched = {:exprs, for(%IR.WithMatchClause{expression: expr} <- clauses, do: expr)}

    clauses_acc = Enum.reduce(clauses, acc, &index_with_clause/2)
    body_acc = index(body, clauses_acc)

    Enum.reduce(else_clauses, body_acc, &index_clause(&1, unmatched, nil, &2))
  end

  defp index(%_struct{} = ir, acc) do
    ir
    |> Map.from_struct()
    |> Map.values()
    |> index(acc)
  end

  defp index(list, acc) when is_list(list), do: Enum.reduce(list, acc, &index/2)

  defp index(tuple, acc) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> index(acc)
  end

  defp index(_ir, acc), do: acc

  defp index_catch(%IR.TryCatchClause{kind: kind, value: value, guards: guards, body: body}, acc) do
    new_acc =
      acc
      |> bind_pattern(kind, :top)
      |> bind_pattern(value, :top)

    index([guards, body], new_acc)
  end

  # A clause whose pattern is matched against the subject; the subject expression is the one the
  # clause is matched against when there is a single one (a case condition), else nil.
  defp index_clause(
         %IR.Clause{match: match, guards: guards, body: body},
         subject,
         subject_expr,
         acc
       ) do
    new_acc =
      acc
      |> bind_pattern(match, subject)
      |> put_subject_extras(subject_expr, match)

    index([guards, body], new_acc)
  end

  defp index_qualifier(%IR.Clause{match: match, guards: guards, body: body}, acc) do
    new_acc = bind_pattern(acc, match, {:elements, body})
    index([guards, body], new_acc)
  end

  defp index_qualifier(%IR.ComprehensionBitstringGenerator{match: match, body: body}, acc) do
    new_acc = bind_pattern(acc, match, {:expr, body})
    index(body, new_acc)
  end

  defp index_qualifier(%IR.ComprehensionFilter{expression: expr}, acc), do: index(expr, acc)

  defp index_rescue(%IR.TryRescueClause{variable: nil, body: body}, acc), do: index(body, acc)

  defp index_rescue(%IR.TryRescueClause{variable: variable, modules: modules, body: body}, acc) do
    module_atoms = for %IR.AtomType{value: module} <- modules, do: module
    new_acc = bind_pattern(acc, variable, {:rescue, module_atoms})
    index(body, new_acc)
  end

  defp index_with_clause(
         %IR.WithMatchClause{match: match, guards: guards, expression: expr},
         acc
       ) do
    new_acc =
      expr
      |> index(acc)
      |> bind_pattern(match, {:expr, expr})
      |> put_subject_extras(expr, match)

    index(guards, new_acc)
  end

  defp index_with_clause(%IR.WithBareClause{expression: expr}, acc), do: index(expr, acc)

  # A map or a struct, from its key and value pairs and what each key and value gives.
  defp map_shape(pairs, shapes_fun) do
    case List.keytake(pairs, %IR.AtomType{value: :__struct__}, 0) do
      {{_key, %IR.AtomType{value: module}}, fields} ->
        {:struct, module, pair_shapes(fields, shapes_fun)}

      _no_struct_key ->
        {:map, pair_shapes(pairs, shapes_fun)}
    end
  end

  defp may_match?(_shape, %IR.MatchPlaceholder{}), do: true

  defp may_match?(_shape, %IR.PinOperator{}), do: true

  defp may_match?(_shape, %IR.Variable{}), do: true

  defp may_match?(shape, %IR.MatchOperator{left: left, right: right}) do
    may_match?(shape, left) and may_match?(shape, right)
  end

  defp may_match?(shape, pattern) do
    opaque?(shape) or structurally_may_match?(shape, pattern)
  end

  # The clauses of each function of the module, by name and arity, none for a module with no IR. A
  # module's IR is read out of the IR PLT once per run (see run/1) and kept in the process
  # dictionary, since a read copies the whole module out of ETS and some generated modules hold
  # over a hundred megabytes of IR.
  defp module_functions(module, ctx) do
    key = {__MODULE__, :functions, module}

    with nil <- Process.get(key) do
      functions = read_module_functions(module, ctx)
      Process.put(key, functions)
      functions
    end
  end

  # Whether a pattern names a type: an alias, or a struct, whose module is one.
  defp names_type?(%IR.AtomType{value: value}) do
    value
    |> Atom.to_string()
    |> String.starts_with?("Elixir.")
  end

  defp names_type?(%IR.PinOperator{}), do: false

  defp names_type?(%_struct{} = ir) do
    ir
    |> Map.from_struct()
    |> Map.values()
    |> names_type?()
  end

  defp names_type?(list) when is_list(list), do: Enum.any?(list, &names_type?/1)

  defp names_type?(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> names_type?()
  end

  defp names_type?(_ir), do: false

  defp opaque?(shape) when is_tuple(shape), do: elem(shape, 0) in @opaque_kinds

  defp opaque?(_shape), do: false

  defp pair_shapes(pairs, shapes_fun) do
    pairs
    |> Enum.flat_map(fn {key, value} -> [key, value] end)
    |> Enum.map(shapes_fun)
    |> union()
  end

  # The indexes of the params the shapes hold, at any depth.
  defp param_indexes({:param, index}, acc), do: MapSet.put(acc, index)

  defp param_indexes(set, acc) when is_struct(set, MapSet) do
    Enum.reduce(set, acc, &param_indexes/2)
  end

  defp param_indexes(list, acc) when is_list(list), do: Enum.reduce(list, acc, &param_indexes/2)

  defp param_indexes(tuple, acc) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> param_indexes(acc)
  end

  defp param_indexes(_term, acc), do: acc

  defp params(arity), do: MapSet.new(0..(arity - 1)//1, &{:param, &1})

  # The shapes a pattern names, a variable, a placeholder or a pin naming nothing.
  defp pattern_shapes(%IR.AtomType{value: value}), do: MapSet.new([{:atom, value}])

  defp pattern_shapes(%IR.ConsOperator{head: head, tail: tail}) do
    elements =
      tail
      |> pattern_shapes()
      |> contents()
      |> MapSet.union(pattern_shapes(head))

    MapSet.new([{:list, elements}])
  end

  defp pattern_shapes(%IR.ListType{data: data}) do
    elements =
      data
      |> Enum.map(&pattern_shapes/1)
      |> union()

    MapSet.new([{:list, elements}])
  end

  defp pattern_shapes(%IR.MapType{data: data}) do
    MapSet.new([map_shape(data, &pattern_shapes/1)])
  end

  defp pattern_shapes(%IR.MatchOperator{left: left, right: right}) do
    union([pattern_shapes(left), pattern_shapes(right)])
  end

  defp pattern_shapes(%IR.TupleType{data: data}) do
    MapSet.new([{:tuple, Enum.map(data, &pattern_shapes/1)}])
  end

  defp pattern_shapes(%type{}) when type in @primitive_types, do: MapSet.new([:prim])

  defp pattern_shapes(_pattern), do: MapSet.new()

  # The variables a pattern binds, a pinned one being read, not bound.
  defp pattern_variables(%IR.PinOperator{}, vars), do: vars

  defp pattern_variables(%IR.Variable{version: nil}, vars), do: vars

  defp pattern_variables(%IR.Variable{name: name, version: version}, vars) do
    [{name, version} | vars]
  end

  defp pattern_variables(%_struct{} = ir, vars) do
    ir
    |> Map.from_struct()
    |> Map.values()
    |> pattern_variables(vars)
  end

  defp pattern_variables(list, vars) when is_list(list) do
    Enum.reduce(list, vars, &pattern_variables/2)
  end

  defp pattern_variables(tuple, vars) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> pattern_variables(vars)
  end

  defp pattern_variables(_ir, vars), do: vars

  defp put_binding(acc, var, binding) do
    %{acc | bindings: Map.update(acc.bindings, var, [binding], &[binding | &1])}
  end

  # Adds what the pattern names to the variable's shapes, when it names a type (see the contract).
  defp put_extras(acc, var, pattern) do
    if names_type?(pattern) do
      shapes = pattern_shapes(pattern)
      %{acc | extras: Map.update(acc.extras, var, shapes, &MapSet.union(&1, shapes))}
    else
      acc
    end
  end

  # A variable matched against a part of a pattern (`%User{} = user`, either way round) takes what
  # that part names.
  defp put_pattern_extras(acc, %IR.MatchOperator{left: left, right: right}) do
    acc
    |> put_side_extras(left, right)
    |> put_side_extras(right, left)
    |> put_pattern_extras(left)
    |> put_pattern_extras(right)
  end

  defp put_pattern_extras(acc, %IR.PinOperator{}), do: acc

  defp put_pattern_extras(acc, %_struct{} = ir) do
    values =
      ir
      |> Map.from_struct()
      |> Map.values()

    put_pattern_extras(acc, values)
  end

  defp put_pattern_extras(acc, list) when is_list(list) do
    Enum.reduce(list, acc, &put_pattern_extras(&2, &1))
  end

  defp put_pattern_extras(acc, tuple) when is_tuple(tuple) do
    put_pattern_extras(acc, Tuple.to_list(tuple))
  end

  defp put_pattern_extras(acc, _ir), do: acc

  defp put_side_extras(acc, %IR.Variable{name: name, version: version}, pattern)
       when version != nil do
    put_extras(acc, {name, version}, pattern)
  end

  defp put_side_extras(acc, _side, _pattern), do: acc

  # A variable matched as a whole against a pattern (a case condition, the right side of a match, a
  # with clause's expression) takes what the pattern names.
  defp put_subject_extras(acc, subject_expr, pattern) do
    put_side_extras(acc, subject_expr, pattern)
  end

  # Adds the types the shapes hold to the accumulator (see types/2).
  defp put_types(shapes, acc, module_info_plt) when is_struct(shapes, MapSet) do
    Enum.reduce(shapes, acc, &put_types(&1, &2, module_info_plt))
  end

  defp put_types({:atom, atom}, acc, module_info_plt) do
    case PLT.get(module_info_plt, atom) do
      {:ok, %{struct?: true}} ->
        %{acc | modules: MapSet.put(acc.modules, atom), structs: MapSet.put(acc.structs, atom)}

      {:ok, _info} ->
        %{acc | modules: MapSet.put(acc.modules, atom)}

      :error ->
        acc
    end
  end

  defp put_types({:struct, module, fields}, acc, module_info_plt) do
    put_types(fields, %{acc | structs: MapSet.put(acc.structs, module)}, module_info_plt)
  end

  defp put_types({:reach, vertex}, acc, _module_info_plt) do
    %{acc | reach: MapSet.put(acc.reach, vertex)}
  end

  defp put_types({:tuple, elements}, acc, module_info_plt) do
    Enum.reduce(elements, acc, &put_types(&1, &2, module_info_plt))
  end

  defp put_types({kind, inner}, acc, module_info_plt) when kind in [:bag, :list, :map] do
    put_types(inner, acc, module_info_plt)
  end

  defp put_types({:fun, _ref, returned}, acc, module_info_plt) do
    put_types(returned, acc, module_info_plt)
  end

  defp put_types({:call, fun, args}, acc, module_info_plt) do
    Enum.reduce([fun | args], acc, &put_types(&1, &2, module_info_plt))
  end

  defp put_types({:dyn, module, _name, _arity, args}, acc, module_info_plt) do
    Enum.reduce([module | args], acc, &put_types(&1, &2, module_info_plt))
  end

  # A primitive, a param or an anonymous function's argument.
  defp put_types(_shape, acc, _module_info_plt), do: acc

  defp read_module_functions(module, ctx) do
    case Compiler.module_ir(ctx.flow.ir_plt, module) do
      {:ok, module_def} ->
        module_def
        |> IR.aggregate_module_funs()
        |> Map.new(fn {name_arity, {_visibility, clauses}} -> {name_arity, clauses} end)

      :error ->
        %{}
    end
  end

  # The variable's shapes, from the innermost frame that knows it, read once per frame.
  defp read_variable(var, ctx) do
    case Enum.find(ctx.frames, &(Map.has_key?(&1.bindings, var) or Map.has_key?(&1.extras, var))) do
      nil ->
        top(ctx.mfa)

      frame ->
        key = {frame.id, var}

        case :ets.lookup(ctx.memo, key) do
          # A variable whose binding reads itself (a reducer's accumulator).
          [{^key, :in_progress}] ->
            top(ctx.mfa)

          [{^key, shapes}] ->
            shapes

          [] ->
            :ets.insert(ctx.memo, {key, :in_progress})
            shapes = variable_shapes(frame, var, ctx)
            :ets.insert(ctx.memo, {key, shapes})
            shapes
        end
    end
  end

  # Runs a public entry with an ETS table the variables' shapes are kept in once read (see
  # read_variable/2), and forgets the modules' functions it read (see module_functions/2) when done.
  # An entry never runs inside another one.
  defp run(fun) do
    memo = :ets.new(__MODULE__, [:set, :private])

    try do
      fun.(memo)
    after
      :ets.delete(memo)

      for {{__MODULE__, :functions, _module} = key, _functions} <- Process.get() do
        Process.delete(key)
      end
    end
  end

  defp shape_contents({:atom, _atom}), do: MapSet.new()

  defp shape_contents(:prim), do: MapSet.new()

  defp shape_contents({:struct, _module, fields}), do: fields

  defp shape_contents({:tuple, elements}), do: union(elements)

  defp shape_contents({kind, inner}) when kind in [:bag, :list, :map], do: inner

  defp shape_contents(opaque), do: MapSet.new([opaque])

  # What the fields argument of a __struct__/1 call puts in the struct: the keys and values of the
  # keyword list or map it is, two levels down.
  defp struct_fields(arg, ctx) do
    arg
    |> eval(ctx)
    |> contents()
    |> contents()
  end

  defp structurally_may_match?({:atom, value}, %IR.AtomType{value: value}), do: true

  defp structurally_may_match?({:tuple, elements}, %IR.TupleType{data: patterns})
       when length(elements) == length(patterns) do
    elements
    |> Enum.zip(patterns)
    |> Enum.all?(fn {element, pattern} -> Enum.any?(element, &may_match?(&1, pattern)) end)
  end

  defp structurally_may_match?({:list, _elements}, %IR.ListType{}), do: true

  defp structurally_may_match?({:list, _elements}, %IR.ConsOperator{}), do: true

  defp structurally_may_match?({:map, _inner}, %IR.MapType{}), do: true

  defp structurally_may_match?({:struct, module, _fields}, %IR.MapType{data: pairs}) do
    case List.keyfind(pairs, %IR.AtomType{value: :__struct__}, 0) do
      {_key, %IR.AtomType{value: pattern_module}} -> pattern_module == module
      _no_named_module -> true
    end
  end

  defp structurally_may_match?(:prim, %type{}) when type in @primitive_types, do: true

  defp structurally_may_match?(_shape, _pattern), do: false

  # The value a binding matches its pattern against.
  defp subject_shapes({:expr, expr}, ctx), do: eval(expr, ctx)

  defp subject_shapes({:exprs, exprs}, ctx), do: eval_all(exprs, ctx)

  # A comprehension generator binds each element of what it iterates over.
  defp subject_shapes({:elements, expr}, ctx) do
    expr
    |> eval(ctx)
    |> contents()
  end

  defp subject_shapes({:param, index}, _ctx), do: MapSet.new([{:param, index}])

  # A rescue without modules takes any exception, raised anywhere the function reaches.
  defp subject_shapes({:rescue, []}, ctx), do: top(ctx.mfa)

  # An exception raised where the function reaches, of one of the modules, holding anything.
  defp subject_shapes({:rescue, modules}, ctx) do
    fields = top(ctx.mfa)
    MapSet.new(modules, &{:struct, &1, fields})
  end

  defp subject_shapes(:top, ctx), do: top(ctx.mfa)

  # A shape with the given arguments put in for its params (see apply_summary/2). The rule before
  # this module applied from a vertex holds no params.
  defp substitute({:param, index}, args), do: Enum.at(args, index, MapSet.new())

  defp substitute({:struct, module, fields}, args) do
    MapSet.new([{:struct, module, apply_summary(fields, args)}])
  end

  defp substitute({kind, inner}, args) when kind in [:bag, :list, :map] do
    MapSet.new([{kind, apply_summary(inner, args)}])
  end

  defp substitute({:tuple, elements}, args) do
    MapSet.new([{:tuple, Enum.map(elements, &apply_summary(&1, args))}])
  end

  defp substitute({:fun, ref, returned}, args) do
    MapSet.new([{:fun, ref, apply_summary(returned, args)}])
  end

  defp substitute({:call, fun, call_args}, args) do
    MapSet.new([
      {:call, apply_summary(fun, args), Enum.map(call_args, &apply_summary(&1, args))}
    ])
  end

  defp substitute({:dyn, module, name, arity, call_args}, args) do
    MapSet.new([
      {:dyn, apply_summary(module, args), name, arity,
       Enum.map(call_args, &apply_summary(&1, args))}
    ])
  end

  defp substitute(shape, _args), do: MapSet.new([shape])

  defp union(sets), do: Enum.reduce(sets, MapSet.new(), &MapSet.union/2)

  defp variable_shapes(frame, var, ctx) do
    frame.bindings
    |> Map.get(var, [])
    |> Enum.map(fn {pattern, subject} -> extract(subject_shapes(subject, ctx), pattern, var) end)
    |> union()
    |> MapSet.union(Map.get(frame.extras, var, MapSet.new()))
  end
end
