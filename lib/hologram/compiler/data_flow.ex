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
  #   6. A value from outside the code (a database row, a message, one read from the session) holds
  #      only the types the code names for it, as before this module: a variable matched against a
  #      pattern that names a module or a struct holds what the pattern names. A value put in the
  #      session, a cookie or the stash stays in the server struct, so it counts as reaching the
  #      client: another handler can read it back.

  alias Hologram.Commons.PLT
  alias Hologram.Commons.Types, as: T
  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.DataFlow.Models
  alias Hologram.Compiler.DataFlow.ShapeSet
  alias Hologram.Compiler.Digraph
  alias Hologram.Compiler.IR

  # How many alternatives a set of shapes can hold before widen/1 makes it a bag.
  @max_alternatives 32

  # The functions that broadcast an action with params, with the index of the params argument.
  @broadcast_params_indexes %{
    {Hologram.Component, :put_broadcast, 4} => 3,
    {Hologram.Component, :put_broadcast_except, 5} => 4,
    {Hologram.Realtime, :broadcast_action, 3} => 2,
    {Hologram.Realtime, :broadcast_action_except, 4} => 3
  }

  # How deep a set of shapes can be inside structs, maps, lists, tuples and the other shapes that hold
  # sets, before widen/1 makes it a bag.
  @max_depth 3

  # How many times the solver evaluates a function before its answer becomes a bag of its leaves (see
  # evaluate/2): a recursive function whose value nests one level deeper on every evaluation would grow
  # without end, while a loop of functions whose answers settle needs far fewer evaluations.
  @evaluations_before_leaves 8

  # How many times the solver evaluates a function before its answer is its top (see top/1), which never
  # changes, so the solve ends (see evaluate/2). With pending calls and anonymous functions dissolved
  # into their parts (see shape_leaves/1), a bag of leaves stops growing unless a call on a module not
  # known yet nests inside another one on every evaluation; this is for that, and for what else keeps
  # an answer changing.
  @evaluations_before_top 16

  # How many calls of anonymous functions one substitution makes in total, in all its branches, before
  # the rest are left unmade (see call_fun/3): a function given itself can call itself without end,
  # and one of several functions given itself calls each of them at every level, so a count of the
  # calls one inside another would still let the work double at every level.
  @max_fun_calls 32

  # How large a function's summary, or the value of a call, can be, in bytes of its external term
  # format (see :erlang.external_size/1, a walk of the whole term like every walk the analysis makes
  # over it), before the function's top stands for it (see capped_summary/3 and capped_call/4).
  # Without a cap a summary can grow to megabytes: a bag holds any number of leaves, and a pending
  # call or an anonymous function in it keeps its own sets. Every call that uses a summary walks it
  # several times (param_indexes/2, replace/3, widen/1), so a few such summaries stall a compile. A
  # start/3 opt can set another cap.
  @max_summary_size 32_768

  # The range of the hash that tells anonymous functions apart within a function (see eval/2).
  @fun_hash_range 4_294_967_296

  # Shapes of values whose structure is known: what is inside them can be taken out.
  @data_kinds [:list, :map, :struct, :tuple]

  # Shapes that stand for a value not known yet, which a caller's arguments or an anonymous
  # function's arguments make known (see replace/3).
  @pending_kinds [:arg, :as_map, :call, :contents, :dot, :dyn, :param, :part]

  # Shapes of unknown structure: they can hold anything, so they can match any pattern.
  @opaque_kinds [:bag, :reach | @pending_kinds]

  # The steps a value takes into an argument that is not known yet (see collapse_route/1).
  @route_steps [:as_map, :contents, :part]

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
  #   * `:prim` - a value holding no types: a number, a binary, a pid, a port, a reference, an atom
  #     the code does not name, or a list, a tuple or a map of those. Its structure is not known, so
  #     it can match any pattern, and every part of it is `:prim` too.
  #   * `{:struct, module, shapes}` - a struct of the module, with what is in its fields.
  #   * `{:map, shapes}` - a map, with its keys and values.
  #   * `{:tuple, [shapes]}` - a tuple, with its elements in order.
  #   * `{:list, shapes}` - a list, with its elements.
  #   * `{:bag, shapes}` - a value of unknown structure holding the shapes.
  #   * `{:fun, ref, shapes}` - an anonymous function and what it returns, in terms of its own
  #     arguments. The ref tells it apart from the other anonymous functions: the function it is
  #     written in and a hash of its IR, the same on every pass over that function.
  #   * `{:param, index}` - whatever the function being summarised is given as that argument.
  #   * `{:arg, ref, index}` - whatever the anonymous function is given as that argument.
  #   * `{:reach, vertex}` - the rule before this module, applied from the vertex (see the contract).
  #   * `{:call, shapes, [shapes]}` - a call of a function value that depends on a parameter.
  #   * `{:as_map, shapes}` - whichever of the shapes' values is a map or a struct: a variable a
  #     pattern matched as a whole against a map pattern (`%{} = value`), or a rescued exception.
  #   * `{:contents, shapes}` - what is inside a value that depends on a parameter, one level down
  #     (see contents/1).
  #   * `{:part, shapes}` - a part, at any depth, of a value that depends on a parameter (see
  #     parts/1).
  #   * `{:dot, shapes, name}` - `value.name` on a value that depends on a parameter: a field of a
  #     map or a struct, or a call of a zero-arity function of a module.
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
          | {:fun, fun_ref, shapes}
          | {:param, non_neg_integer}
          | {:arg, fun_ref, non_neg_integer}
          | {:reach, CallGraph.vertex()}
          | {:call, shapes, [shapes]}
          | {:as_map, shapes}
          | {:contents, shapes}
          | {:part, shapes}
          | {:dot, shapes, atom}
          | {:dyn, shapes, atom, arity, [shapes]}

  @type fun_ref :: {mfa, non_neg_integer}

  @type shapes :: ShapeSet.t()

  # What a compile's analysis works with: the IR PLT the code is read from (and where missing IR is
  # built), the module info PLT, and the summaries of the functions it has followed so far.
  @type t :: %{
          ir_plt: PLT.t(),
          max_summary_size: pos_integer,
          module_info_plt: PLT.t(),
          summaries: PLT.t()
        }

  # The types shapes hold (see types/2).
  @type types :: %{
          modules: MapSet.t(module),
          reach: MapSet.t(CallGraph.vertex()),
          structs: MapSet.t(module)
        }

  @doc """
  Returns the shapes a summary (see `summary/2`) gives for a call with arguments of the given
  shapes: each `{:param, index}` in it, at any depth, replaced with the argument's shapes. A missing
  argument gives nothing. A call of an anonymous function that a param stood for is made once the
  param is replaced. A dynamic call or a dot on a module a param stood for is left as it is: making
  it needs the analysis (the calls made while summarising do).
  """
  @spec apply_summary(shapes, [shapes]) :: shapes
  def apply_summary(summary, args), do: put_args(summary, args, nil)

  @doc """
  Returns what the given function, which broadcasts actions (see
  `Hologram.Reflection.broadcast_mfas/0`), sends to the clients, in the shape of
  `Hologram.Compiler.CallGraph.broadcast_caller_analysis/2`'s results: the protocol dispatch types
  and the component modules the params of its broadcasts hold, found the way
  `server_callback_analysis/3` finds them. A broadcast inside an anonymous function counts, a value
  that comes from the function's own params holds nothing, as the rule before this module walked
  from the function and not from its callers.
  """
  @spec broadcast_analysis(Digraph.t(), mfa, t) :: CallGraph.broadcast_caller_analysis()
  def broadcast_analysis(graph, caller, flow) do
    sent =
      run(flow, fn ctx ->
        caller_ctx = %{ctx | mfa: caller}

        settle(caller_ctx, fn -> caller_broadcast_params(caller, caller_ctx) end)
      end)

    {dispatch_types, components} = reaching_types(sent, graph, flow)
    %{dispatch_types: dispatch_types, referenced_components: components}
  end

  @doc """
  Returns whether the given expression, in the given clause of the given function, certainly gives a
  map or a struct: it gives something (it can return), and every alternative is a map, a struct, or
  a value a map pattern matched (see `shapes/4`). Such a value is never a module, so a call of a
  function on it is no call of a module's function (see `Hologram.Compiler.DynamicCallGate`).
  """
  @spec definite_map?(IR.t(), IR.FunctionClause.t(), mfa, t) :: boolean
  def definite_map?(expr, clause, mfa, flow) do
    shapes = shapes(expr, clause, mfa, flow)
    not ShapeSet.empty?(shapes) and ShapeSet.all?(shapes, &map_shape?/1)
  end

  @doc """
  Returns what the server callbacks of the given templatable (its init/3 and command/3) can hand to
  the client, in the shape of `Hologram.Compiler.CallGraph.server_callback_analysis/3`'s results:

    * `:dispatch_types` - the types that can appear at protocol dispatch on the client: the structs
      the values the callbacks return hold, and the types the graph walk below finds.
    * `:server_referenced_components` - the component modules those values hold, and the ones the
      graph walk finds, sorted.

  The callbacks are followed with nothing known about their arguments: params and props come from
  the client, which has their types already, and the server struct holds what the code names for
  it. The values they return go to the client: the component's state, context, next action,
  command and page, and the server's next action and broadcasts, and the server's session, cookies
  and stash too, which another handler can read back and hand on. What the server is only told (its
  status, a redirect, a response, the user id, the subscriptions) is dropped on the way in (see
  `Hologram.Compiler.DataFlow.Models`).

  Where the analysis could not follow the code, the rule before it applies from there: the given
  graph is walked from those vertices (see `top/1`), protocol functions not entered, and so it is
  from each struct module found, whose vertex has edges to what the struct needs (an Ecto schema's
  related schemas).
  """
  @spec server_callback_analysis(Digraph.t(), module, t) :: CallGraph.server_callback_analysis()
  def server_callback_analysis(graph, templatable, flow) do
    returned =
      run(flow, fn ctx ->
        no_args = [ShapeSet.new(), ShapeSet.new(), ShapeSet.new()]

        settle(ctx, fn ->
          [{templatable, :command, 3}, {templatable, :init, 3}]
          |> Enum.map(&summary_with_args(&1, no_args, ctx))
          |> ShapeSet.union_all()
        end)
      end)

    {dispatch_types, components} = reaching_types(returned, graph, flow)
    %{dispatch_types: dispatch_types, server_referenced_components: components}
  end

  @doc """
  Returns the shapes of the value the given expression gives, where the expression is in the given
  clause of the given function: a variable holds what its binding in the clause gives, and a
  parameter of the clause is `{:param, index}`.
  """
  @spec shapes(IR.t(), IR.FunctionClause.t(), mfa, t) :: shapes
  def shapes(expr, clause, mfa, flow) do
    run(flow, fn ctx ->
      expr_ctx = %{ctx | mfa: mfa}

      settle(expr_ctx, fn ->
        frame = clause_frame(clause, &{:param, &1})
        eval(expr, %{expr_ctx | frames: [frame]})
      end)
    end)
  end

  @doc """
  Starts the analysis of a compile, which reads IR from the given IR PLT and module facts from the
  given module info PLT.

  ## Options

    * `:max_summary_size` - how large a function's summary, or the value of a call, can be, in bytes
      of its external term format, before the function's top stands for it (see `top/1`); defaults
      to 32 KiB.

  The other opts are given to the PLT it keeps its summaries in (see `Hologram.Commons.PLT.start/1`:
  a `:supervisor` stops it with the supervisor).
  """
  @spec start(PLT.t(), PLT.t(), T.opts()) :: t
  def start(ir_plt, module_info_plt, opts \\ []) do
    {max_summary_size, plt_opts} = Keyword.pop(opts, :max_summary_size, @max_summary_size)

    %{
      ir_plt: ir_plt,
      max_summary_size: max_summary_size,
      module_info_plt: module_info_plt,
      summaries: PLT.start(plt_opts)
    }
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

  Functions that call each other are solved together: each is evaluated again when an answer it read
  changes, until none changes, the first evaluation reading nothing for a function not evaluated yet.
  An answer that keeps growing becomes a bag of its leaves after a few evaluations. Every function a
  run solves is kept for the rest of the compile. A summary, or the value of a call, larger than the
  cap given to `start/3` is the function's top, with the arguments put in for a call.
  """
  @spec summary(mfa, t) :: shapes
  def summary(mfa, flow) do
    run(flow, fn ctx -> settle(ctx, fn -> callee_summary(mfa, ctx) end) end)
  end

  @doc """
  Returns what the given function's value is when the analysis cannot follow it: the rule before
  this module applied from the function, and everything the function is given.
  """
  @spec top(mfa) :: shapes
  def top({_module, _function, arity} = mfa) do
    arity
    |> params()
    |> ShapeSet.put({:reach, mfa})
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

  # What calling a function value of the given shapes with arguments of the given shapes gives, for
  # each alternative (see replace/3 about rep).
  defp apply_fun(fun_shapes, args, rep) do
    ShapeSet.flat_map(fun_shapes, &call_fun(&1, args, rep))
  end

  # The alternatives of the given shapes that are maps or structs: a value not known yet, or of unknown
  # structure, becomes `{:as_map, ...}`; an atom, a list, a tuple or a function is dropped (a map
  # pattern does not match it).
  defp as_maps(shapes) do
    ShapeSet.flat_map(shapes, &ShapeSet.new(as_map_shapes(&1)))
  end

  defp as_map_shapes({kind, _inner} = shape) when kind in [:as_map, :map], do: [shape]

  defp as_map_shapes({:struct, _module, _fields} = shape), do: [shape]

  defp as_map_shapes(shape)
       when shape == :prim or
              (is_tuple(shape) and elem(shape, 0) in [:bag, :reach | @pending_kinds]) do
    [{:as_map, ShapeSet.new([shape])}]
  end

  defp as_map_shapes(_shape), do: []

  defp bag_of_leaves(shapes), do: ShapeSet.new([{:bag, leaves(shapes)}])

  # Records that every variable of the pattern is bound by matching the pattern against the subject
  # (see subject_shapes/2), and what the pattern names for the variables matched against a part of it.
  defp bind_pattern(acc, pattern, subject) do
    new_acc =
      pattern
      |> pattern_variables([])
      |> Enum.reduce(acc, &put_binding(&2, &1, {pattern, subject}))

    put_pattern_extras(new_acc, pattern)
  end

  # What the params of a broadcast call gives, when the function called is one that broadcasts with
  # params, else nothing.
  defp broadcast_call_params(mfa, args, ctx) do
    case Map.fetch(@broadcast_params_indexes, mfa) do
      {:ok, index} ->
        args
        |> Enum.at(index)
        |> eval(ctx)

      :error ->
        ShapeSet.new()
    end
  end

  # What the params of the broadcasts in the given IR give, each read in the frame it is in: a
  # broadcast inside an anonymous function reads the function's args and the variables it closes over.
  defp broadcast_params(%IR.AnonymousFunctionType{clauses: clauses} = ir, ctx) do
    ref = fun_ref(ir, ctx)

    clauses
    |> Enum.map(fn clause ->
      frame = clause_frame(clause, &{:arg, ref, &1})
      broadcast_params(clause.body, %{ctx | frames: [frame | ctx.frames]})
    end)
    |> ShapeSet.union_all()
  end

  defp broadcast_params(
         %IR.RemoteFunctionCall{
           module: %IR.AtomType{value: :erlang},
           function: :apply,
           args: [
             %IR.AtomType{value: module},
             %IR.AtomType{value: name},
             %IR.ListType{data: args}
           ]
         } = ir,
         ctx
       ) do
    ShapeSet.union_all([
      broadcast_call_params({module, name, length(args)}, args, ctx),
      broadcast_params_inside(ir, ctx)
    ])
  end

  defp broadcast_params(
         %IR.RemoteFunctionCall{module: %IR.AtomType{value: module}, function: name, args: args} =
           ir,
         ctx
       ) do
    ShapeSet.union_all([
      broadcast_call_params({module, name, length(args)}, args, ctx),
      broadcast_params_inside(ir, ctx)
    ])
  end

  defp broadcast_params(%_struct{} = ir, ctx), do: broadcast_params_inside(ir, ctx)

  defp broadcast_params(list, ctx) when is_list(list) do
    list
    |> Enum.map(&broadcast_params(&1, ctx))
    |> ShapeSet.union_all()
  end

  defp broadcast_params(tuple, ctx) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> broadcast_params(ctx)
  end

  defp broadcast_params(_ir, _ctx), do: ShapeSet.new()

  defp broadcast_params_inside(ir, ctx) do
    ir
    |> Map.from_struct()
    |> Map.values()
    |> broadcast_params(ctx)
  end

  # A call of the named function on a module of the given shapes, for each alternative: a module
  # atom gives the function's summary with the arguments put in; a value that depends on a param or
  # on an anonymous function's argument keeps the call for when that is known; a value of unknown
  # structure gives itself and the arguments, and the calls on the module atoms it holds; a primitive
  # gives a primitive. Any other value is no module: the call raises.
  defp call_dyn(module_shapes, name, arity, args, ctx) do
    ShapeSet.flat_map(module_shapes, &call_dyn_shape(&1, name, arity, args, ctx))
  end

  defp call_dyn_shape({:atom, module}, name, arity, args, ctx) do
    mfa = {module, name, arity}

    mfa
    |> callee_summary(ctx)
    |> capped_call(mfa, args, ctx)
  end

  defp call_dyn_shape(shape, name, arity, args, _ctx)
       when is_tuple(shape) and elem(shape, 0) in @pending_kinds do
    ShapeSet.new([{:dyn, ShapeSet.new([shape]), name, arity, args}])
  end

  defp call_dyn_shape({:bag, inner} = bag, name, arity, args, ctx) do
    module_atoms = ShapeSet.filter(inner, &match?({:atom, _module}, &1))
    unknown = ShapeSet.new([{:bag, ShapeSet.union_all([ShapeSet.new([bag]) | args])}])

    ShapeSet.union_all([unknown, call_dyn(module_atoms, name, arity, args, ctx)])
  end

  defp call_dyn_shape({:reach, _vertex} = reach, _name, _arity, args, _ctx) do
    ShapeSet.new([{:bag, ShapeSet.union_all([ShapeSet.new([reach]) | args])}])
  end

  # A module the code does not name (an atom made at runtime) gives what the code names for it:
  # nothing (see the contract).
  defp call_dyn_shape(:prim, _name, _arity, _args, _ctx), do: ShapeSet.new([:prim])

  defp call_dyn_shape(_shape, _name, _arity, _args, _ctx), do: ShapeSet.new()

  # An anonymous function returns what it returns with the arguments put in for its own. A function
  # that depends on a param or on an anonymous function's argument is called once that is known (see
  # replace_parts/3). A value of unknown structure can be a function returning anything it holds or
  # it is given. Any other value is no function: calling it raises.
  defp call_fun({:fun, ref, returned} = fun, args, rep) do
    if :counters.get(rep.calls, 1) < @max_fun_calls do
      :counters.add(rep.calls, 1, 1)
      replace(returned, &replace_arg(&1, ref, args), rep)
    else
      ShapeSet.new([{:call, ShapeSet.new([fun]), args}])
    end
  end

  defp call_fun(shape, args, _rep)
       when is_tuple(shape) and elem(shape, 0) in @pending_kinds do
    ShapeSet.new([{:call, ShapeSet.new([shape]), args}])
  end

  defp call_fun(shape, args, _rep) when is_tuple(shape) and elem(shape, 0) in [:bag, :reach] do
    ShapeSet.union_all([ShapeSet.new([shape]) | args])
  end

  defp call_fun(_shape, _args, _rep), do: ShapeSet.new()

  # The summary of a function a call reaches: from the analysis when solved already, else its model
  # (see Hologram.Compiler.DataFlow.Models), else its current answer in the run's solve (see
  # solving_summary/2).
  defp callee_summary(mfa, ctx) do
    case PLT.get(ctx.flow.summaries, mfa) do
      {:ok, summary} -> summary
      :error -> Models.summary(mfa) || solving_summary(mfa, ctx)
    end
  end

  # What the params of the broadcasts in the given function's clauses give, each clause read in a frame
  # of its own made now (see settle/2).
  defp caller_broadcast_params(caller, ctx) do
    caller
    |> function_clauses(ctx)
    |> List.wrap()
    |> Enum.map(fn clause ->
      frame = clause_frame(clause, &{:param, &1})
      broadcast_params(clause.body, %{ctx | frames: [frame]})
    end)
    |> ShapeSet.union_all()
  end

  # The callee's summary with the arguments put in, or the callee's top with them when that value is
  # larger than the flow context's :max_summary_size: the rule before this module applied from the
  # callee, and everything it is given, which holds every type the value holds. Putting arguments in
  # multiplies sizes (a summary holding its param many times, given a large argument), and a value
  # made so is an argument of the next call in the same function, so the check is made at every call,
  # not only on a function's finished summary (see capped_summary/3).
  defp capped_call(summary, mfa, args, ctx) do
    value = put_args(summary, args, ctx)

    if :erlang.external_size(value) > ctx.flow.max_summary_size do
      put_args(top(mfa), args, ctx)
    else
      value
    end
  end

  # The summary, or the function's top when the summary is larger than the flow context's
  # :max_summary_size (see @max_summary_size). The top holds the rule before this module applied from
  # the function and everything it is given, so no type the summary holds is lost, and it is small: the
  # functions that call this one get small summaries too.
  defp capped_summary(summary, mfa, ctx) do
    if :erlang.external_size(summary) > ctx.flow.max_summary_size do
      top(mfa)
    else
      summary
    end
  end

  # The variables of a function clause or an anonymous function's clause, each with the places it is
  # bound at and the shapes the patterns it is matched against name for it; the given function says
  # what the parameter at an index holds. A variable of IR read from a BEAM has a version per
  # binding, so a variable is a name and a version. A capture's parameters (`$1`) have none, and
  # are unique within it.
  defp clause_frame(%IR.FunctionClause{params: params, guards: guards, body: body}, param_subject) do
    acc =
      params
      |> Enum.with_index()
      |> Enum.reduce(%{bindings: %{}, extras: %{}}, fn {param, index}, acc ->
        bind_pattern(acc, param, param_subject.(index))
      end)

    [guards, body]
    |> index(acc)
    |> Map.put(:id, make_ref())
  end

  defp component?(module, module_info_plt) do
    match?({:ok, %{component?: true}}, PLT.get(module_info_plt, module))
  end

  # What the function's code returns, the union over its clauses, read with the answers of the
  # functions it calls as the run's solve has them now (see evaluate/2).
  defp code_summary(mfa, ctx) do
    function_ctx = %{ctx | mfa: mfa}

    mfa
    |> function_clauses(ctx)
    |> Enum.map(fn clause ->
      frame = clause_frame(clause, &{:param, &1})
      eval(clause.body, %{function_ctx | frames: [frame]})
    end)
    |> ShapeSet.union_all()
    |> widen()
    |> capped_summary(mfa, ctx)
  end

  # Collapses routes into arguments: a chain of two or more steps (@route_steps) around params or
  # anonymous function arguments becomes those roots and `{:part, roots}`, the argument itself or
  # anything inside it, which holds every value the chain can give. A single step stays, and so does a
  # dot, which on a module atom calls a function. The chains made answers grow with every way the code
  # takes a piece out of an argument, and no type depends on which way it took.
  defp collapse_route({step, inner}) when step in @route_steps do
    collapsed = collapse_routes(inner)

    case route_roots(collapsed) do
      {:ok, roots} ->
        if ShapeSet.any?(collapsed, &route_step?/1) do
          ShapeSet.put(roots, {:part, roots})
        else
          ShapeSet.new([{step, collapsed}])
        end

      :error ->
        ShapeSet.new([{step, collapsed}])
    end
  end

  defp collapse_route({:struct, module, fields}) do
    ShapeSet.new([{:struct, module, collapse_routes(fields)}])
  end

  defp collapse_route({kind, inner}) when kind in [:bag, :list, :map] do
    ShapeSet.new([{kind, collapse_routes(inner)}])
  end

  defp collapse_route({:tuple, elements}) do
    ShapeSet.new([{:tuple, Enum.map(elements, &collapse_routes/1)}])
  end

  defp collapse_route({:fun, ref, returned}) do
    ShapeSet.new([{:fun, ref, collapse_routes(returned)}])
  end

  defp collapse_route({:call, fun, args}) do
    ShapeSet.new([{:call, collapse_routes(fun), Enum.map(args, &collapse_routes/1)}])
  end

  defp collapse_route({:dot, inner, name}),
    do: ShapeSet.new([{:dot, collapse_routes(inner), name}])

  defp collapse_route({:dyn, module, name, arity, args}) do
    ShapeSet.new([
      {:dyn, collapse_routes(module), name, arity, Enum.map(args, &collapse_routes/1)}
    ])
  end

  defp collapse_route(shape), do: ShapeSet.new([shape])

  defp collapse_routes(shapes), do: ShapeSet.flat_map(shapes, &collapse_route/1)

  # What can be inside a value of the given shapes, one level down. An atom holds nothing, a part of
  # a primitive is a primitive, and a shape of unknown structure holds itself.
  defp contents(shapes) do
    ShapeSet.flat_map(shapes, &shape_contents/1)
  end

  # `value.name` on a value of the given shapes, for each alternative: a module atom gives the
  # summary of the module's zero-arity function; a struct gives its module for __struct__ and what
  # its fields hold for any other name, a map what it holds; a value that depends on a param or on
  # an anonymous function's argument keeps the dot for when that is known; a value of unknown
  # structure gives itself, and the dots on the module atoms it holds; a primitive gives a primitive.
  # Any other value raises.
  defp dot(shapes, name, ctx) do
    ShapeSet.flat_map(shapes, &dot_shape(&1, name, ctx))
  end

  defp dot_shape({:atom, _module} = atom, name, ctx), do: call_dyn_shape(atom, name, 0, [], ctx)

  defp dot_shape({:struct, module, _fields}, :__struct__, _ctx),
    do: ShapeSet.new([{:atom, module}])

  defp dot_shape({:struct, _module, fields}, _name, _ctx), do: fields

  defp dot_shape({:map, inner}, _name, _ctx), do: inner

  defp dot_shape(:prim, _name, _ctx), do: ShapeSet.new([:prim])

  defp dot_shape(shape, name, _ctx)
       when is_tuple(shape) and elem(shape, 0) in @pending_kinds do
    ShapeSet.new([{:dot, ShapeSet.new([shape]), name}])
  end

  defp dot_shape({:bag, inner} = bag, name, ctx) do
    module_atoms = ShapeSet.filter(inner, &match?({:atom, _module}, &1))
    ShapeSet.union_all([ShapeSet.new([bag]), dot(module_atoms, name, ctx)])
  end

  defp dot_shape({:reach, _vertex} = reach, _name, _ctx), do: ShapeSet.new([reach])

  defp dot_shape(_shape, _name, _ctx), do: ShapeSet.new()

  # Puts the function on the run's work list (see solve/1), unless it is there already, keyed by its
  # depth and then by when it was put there.
  defp enqueue(mfa, ctx) do
    if :ets.insert_new(ctx.memo, {{:queued, mfa}, true}) do
      [{_key, depth}] = :ets.lookup(ctx.memo, {:depth, mfa})
      sequence = :ets.update_counter(ctx.memo, :sequence, 1, {:sequence, 0})
      :ets.insert(ctx.work, {{-depth, sequence}, mfa})
    end
  end

  defp eval(%IR.AnonymousFunctionCall{function: function, args: args}, ctx) do
    arg_shapes = Enum.map(args, &eval(&1, ctx))

    function
    |> eval(ctx)
    |> apply_fun(arg_shapes, new_rep(ctx))
  end

  # An anonymous function returns what its clauses give, its parameters being its arguments. A
  # capture comes with a clause that calls the captured function.
  defp eval(%IR.AnonymousFunctionType{clauses: clauses} = ir, ctx) do
    ref = fun_ref(ir, ctx)

    returned =
      clauses
      |> Enum.map(fn clause ->
        frame = clause_frame(clause, &{:arg, ref, &1})
        eval(clause.body, %{ctx | frames: [frame | ctx.frames]})
      end)
      |> ShapeSet.union_all()

    ShapeSet.new([{:fun, ref, returned}])
  end

  defp eval(%IR.AtomType{value: value}, _ctx), do: ShapeSet.new([{:atom, value}])

  defp eval(%IR.Block{expressions: []}, _ctx), do: ShapeSet.new([{:atom, nil}])

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
        ShapeSet.new([{:list, mapped}])

      %IR.MapType{data: []} ->
        ShapeSet.new([{:map, contents(mapped)}])

      _other ->
        inner =
          collectable
          |> eval(ctx)
          |> ShapeSet.union(mapped)

        ShapeSet.new([{:bag, inner}])
    end
  end

  defp eval(%IR.Comprehension{reducer: %{initial_value: initial_value, clauses: clauses}}, ctx) do
    inner = eval_all([initial_value | Enum.map(clauses, & &1.body)], ctx)
    ShapeSet.new([{:bag, inner}])
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
      |> ShapeSet.union(eval(head, ctx))

    ShapeSet.new([{:list, elements}])
  end

  defp eval(%IR.ListType{data: data}, ctx) do
    ShapeSet.new([{:list, eval_all(data, ctx)}])
  end

  defp eval(%IR.DotOperator{left: left, right: %IR.AtomType{value: name}}, ctx) do
    left
    |> eval(ctx)
    |> dot(name, ctx)
  end

  defp eval(%IR.LocalFunctionCall{function: function, args: args}, ctx) do
    {module, _function, _arity} = ctx.mfa
    eval_call({module, function, length(args)}, args, ctx)
  end

  defp eval(%IR.MapType{data: data}, ctx) do
    ShapeSet.new([map_shape(data, &eval(&1, ctx))])
  end

  # The value of a match is its right side.
  defp eval(%IR.MatchOperator{right: right}, ctx), do: eval(right, ctx)

  # apply/3 with the module, the function name and the argument list written out is a call.
  defp eval(
         %IR.RemoteFunctionCall{
           module: %IR.AtomType{value: :erlang},
           function: :apply,
           args: [
             %IR.AtomType{value: module},
             %IR.AtomType{value: name},
             %IR.ListType{data: args}
           ]
         },
         ctx
       ) do
    eval_call({module, name, length(args)}, args, ctx)
  end

  # apply/3 with the function name and the argument list written out is a call on the module.
  defp eval(
         %IR.RemoteFunctionCall{
           module: %IR.AtomType{value: :erlang},
           function: :apply,
           args: [module, %IR.AtomType{value: name}, %IR.ListType{data: args}]
         },
         ctx
       ) do
    arg_shapes = Enum.map(args, &eval(&1, ctx))

    module
    |> eval(ctx)
    |> call_dyn(name, length(args), arg_shapes, ctx)
  end

  # apply/2 with the argument list written out is a call of the function.
  defp eval(
         %IR.RemoteFunctionCall{
           module: %IR.AtomType{value: :erlang},
           function: :apply,
           args: [fun, %IR.ListType{data: args}]
         },
         ctx
       ) do
    arg_shapes = Enum.map(args, &eval(&1, ctx))

    fun
    |> eval(ctx)
    |> apply_fun(arg_shapes, new_rep(ctx))
  end

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
      |> ShapeSet.union_all()

    ShapeSet.new([{:struct, module, fields}])
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

  # A call on a module the code does not name.
  defp eval(%IR.RemoteFunctionCall{module: module, function: function, args: args}, ctx) do
    arg_shapes = Enum.map(args, &eval(&1, ctx))

    module
    |> eval(ctx)
    |> call_dyn(function, length(args), arg_shapes, ctx)
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
    ShapeSet.new([{:tuple, Enum.map(data, &eval(&1, ctx))}])
  end

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

  defp eval(%type{}, _ctx) when type in @primitive_types, do: ShapeSet.new([:prim])

  defp eval(_expr, ctx), do: top(ctx.mfa)

  defp eval_all(exprs, ctx) do
    exprs
    |> Enum.map(&eval(&1, ctx))
    |> ShapeSet.union_all()
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
        if MapSet.member?(used_indexes, index), do: eval(arg, ctx), else: ShapeSet.new()
      end)

    capped_call(summary, mfa, arg_shapes, ctx)
  end

  # Evaluates a function the run is solving: its answer is what its code gives with the current answers
  # of the functions it calls. When the answer changed, the functions that read it are evaluated
  # again, so once the work list is empty every answer is what its code gives with the final answers.
  # The answer so far is not joined in: an evaluation made while a callee answered nothing yet gives
  # alternatives (a list of nothing, a tuple of nothing) that a later answer does not absorb (see
  # evaluated_answer/4 for the answers after many evaluations).
  defp evaluate(mfa, ctx) do
    [{^mfa, old}] = :ets.lookup(ctx.answers, mfa)
    evaluations = :ets.update_counter(ctx.memo, {:evaluations, mfa}, 1, {{:evaluations, mfa}, 0})

    answer = evaluated_answer(mfa, old, evaluations, ctx)

    if answer != old do
      :ets.insert(ctx.answers, {mfa, answer})

      for {^mfa, dependent} <- :ets.lookup(ctx.dependents, mfa) do
        enqueue(dependent, ctx)
      end
    end
  end

  # The answer of an evaluation, by how many evaluations the function had: what its code gives; past
  # @evaluations_before_leaves, a bag of the leaves of the answer so far and what its code gives, so
  # the answer only grows and its growth ends with its leaves (see shape_leaves/1); past
  # @evaluations_before_top, its top, which never changes, so the solve ends whatever keeps the answer
  # changing. The top holds every type the function can give (see the contract).
  defp evaluated_answer(mfa, _old, evaluations, _ctx)
       when evaluations > @evaluations_before_top do
    top(mfa)
  end

  defp evaluated_answer(mfa, old, evaluations, ctx)
       when evaluations > @evaluations_before_leaves do
    new = code_summary(mfa, %{ctx | node: mfa})
    ShapeSet.new([{:bag, leaves(ShapeSet.union(old, new))}])
  end

  defp evaluated_answer(mfa, _old, _evaluations, ctx), do: code_summary(mfa, %{ctx | node: mfa})

  # The part of a value of the given shapes that the pattern binds to the variable, from the
  # alternatives the pattern can match.
  defp extract(shapes, pattern, var) do
    shapes
    |> ShapeSet.filter(&may_match?(&1, pattern))
    |> ShapeSet.flat_map(&extract_shape(&1, pattern, var))
  end

  defp extract_shape(shape, %IR.Variable{name: name, version: version}, {name, version}) do
    ShapeSet.new([shape])
  end

  # A variable matched as a whole against a map pattern (`%{} = value`, either way round) holds only
  # the alternatives that are maps or structs.
  defp extract_shape(shape, %IR.MatchOperator{left: left, right: right}, var) do
    extracted =
      ShapeSet.union_all([extract_shape(shape, left, var), extract_shape(shape, right, var)])

    if matched_as_map?(left, right, var) or matched_as_map?(right, left, var) do
      as_maps(extracted)
    else
      extracted
    end
  end

  # A variable in a binary pattern takes a binary or a number.
  defp extract_shape(_shape, %IR.BitstringType{} = pattern, var) do
    if var in pattern_variables(pattern, []), do: ShapeSet.new([:prim]), else: ShapeSet.new()
  end

  defp extract_shape({:tuple, elements}, %IR.TupleType{data: patterns}, var) do
    elements
    |> Enum.zip(patterns)
    |> Enum.map(fn {element, pattern} -> extract(element, pattern, var) end)
    |> ShapeSet.union_all()
  end

  defp extract_shape({:list, elements}, %IR.ListType{data: patterns}, var) do
    patterns
    |> Enum.map(&extract(elements, &1, var))
    |> ShapeSet.union_all()
  end

  defp extract_shape({:list, elements} = shape, %IR.ConsOperator{head: head, tail: tail}, var) do
    ShapeSet.union_all([extract(elements, head, var), extract(ShapeSet.new([shape]), tail, var)])
  end

  defp extract_shape({:struct, module, fields}, %IR.MapType{data: pairs}, var) do
    pairs
    |> Enum.map(fn
      {%IR.AtomType{value: :__struct__}, value} ->
        extract(ShapeSet.new([{:atom, module}]), value, var)

      {key, value} ->
        ShapeSet.union_all([extract(fields, key, var), extract(fields, value, var)])
    end)
    |> ShapeSet.union_all()
  end

  defp extract_shape({:map, inner}, %IR.MapType{data: pairs}, var) do
    pairs
    |> Enum.map(fn {key, value} ->
      ShapeSet.union_all([extract(inner, key, var), extract(inner, value, var)])
    end)
    |> ShapeSet.union_all()
  end

  # A variable inside a pattern matched against a value of unknown structure takes a part of it (see
  # parts/1).
  defp extract_shape(shape, pattern, var) do
    if (opaque?(shape) or shape == :prim) and var in pattern_variables(pattern, []) do
      parts(ShapeSet.new([shape]))
    else
      ShapeSet.new()
    end
  end

  # What tells an anonymous function apart: the function it is written in and a hash of its IR, the
  # same on every pass over that function.
  defp fun_ref(ir, ctx), do: {ctx.mfa, :erlang.phash2(ir, @fun_hash_range)}

  defp function_clauses({module, function, arity}, ctx) do
    module
    |> module_functions(ctx)
    |> Map.get({function, arity})
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

  # Every shape the given shapes hold, at any depth, flat: a struct with no fields besides what its
  # fields hold, and the contents of maps, lists, tuples and bags. An anonymous function and a call of
  # one not made yet dissolve into their parts: what the function returns, the function called and the
  # arguments. That holds every type the call can give, since a function returns what it builds or
  # what it is given, and a bag is called the same way either way (see call_fun/3). A dynamic call, a
  # dot and a step into a value not known yet stay, with the sets they hold made leaves too: a call on
  # a module not known yet gives what that module's function builds, which its parts don't hold.
  defp leaves(shapes) do
    ShapeSet.flat_map(shapes, &ShapeSet.new(shape_leaves(&1)))
  end

  # A map or a struct, from its key and value pairs and what each key and value gives.
  defp map_shape(pairs, shapes_fun) do
    case List.keytake(pairs, %IR.AtomType{value: :__struct__}, 0) do
      {{_key, %IR.AtomType{value: module}}, fields} ->
        {:struct, module, pair_shapes(fields, shapes_fun)}

      _no_struct_key ->
        {:map, pair_shapes(pairs, shapes_fun)}
    end
  end

  defp map_shape?({kind, _inner}) when kind in [:as_map, :map], do: true

  defp map_shape?({:struct, _module, _fields}), do: true

  defp map_shape?(_shape), do: false

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

  # Whether the pattern is the given variable and the other side of the match a map or struct pattern.
  defp matched_as_map?(
         %IR.Variable{name: name, version: version},
         %IR.MapType{},
         {name, version}
       ),
       do: true

  defp matched_as_map?(_pattern, _other_side, _var), do: false

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

  defp nested_shape_list(shape) when is_tuple(shape) and elem(shape, 0) in @data_kinds do
    shape
    |> nested_shapes()
    |> ShapeSet.to_list()
  end

  defp nested_shape_list(_shape), do: []

  # Everything inside a struct, a map, a list or a tuple, at any depth: the shapes inside it, and
  # what is inside those of them that are structs, maps, lists or tuples.
  defp nested_shapes({:struct, _module, fields}), do: with_nested_shapes(fields)

  defp nested_shapes({:tuple, elements}) do
    elements
    |> ShapeSet.union_all()
    |> with_nested_shapes()
  end

  defp nested_shapes({kind, inner}) when kind in [:list, :map], do: with_nested_shapes(inner)

  # What a substitution carries through replace/3: the ctx, or nil, and a counter of the calls of
  # anonymous functions it made, one cell every branch adds to (see @max_fun_calls).
  defp new_rep(ctx), do: %{calls: :counters.new(1, []), ctx: ctx}

  defp opaque?(shape) when is_tuple(shape), do: elem(shape, 0) in @opaque_kinds

  defp opaque?(_shape), do: false

  defp pair_shapes(pairs, shapes_fun) do
    pairs
    |> Enum.flat_map(fn {key, value} -> [key, value] end)
    |> Enum.map(shapes_fun)
    |> ShapeSet.union_all()
  end

  # The indexes of the params the shapes hold, at any depth.
  defp param_indexes({:param, index}, acc), do: MapSet.put(acc, index)

  defp param_indexes(list, acc) when is_list(list), do: Enum.reduce(list, acc, &param_indexes/2)

  defp param_indexes(tuple, acc) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> param_indexes(acc)
  end

  defp param_indexes(_term, acc), do: acc

  defp params(arity) do
    0..(arity - 1)//1
    |> Enum.map(&{:param, &1})
    |> ShapeSet.new()
  end

  # A part, at any depth, of a value of the given shapes, for each alternative: a value that depends
  # on a parameter gives `{:part, ...}` for when it is known; a value of unknown structure and a
  # primitive give themselves; a struct, a map, a list or a tuple give what is inside them at any
  # depth, in a bag; an atom and a function have no parts.
  defp parts(shapes) do
    ShapeSet.flat_map(shapes, &shape_parts/1)
  end

  # The shapes a pattern names, a variable, a placeholder or a pin naming nothing.
  defp pattern_shapes(%IR.AtomType{value: value}), do: ShapeSet.new([{:atom, value}])

  defp pattern_shapes(%IR.ConsOperator{head: head, tail: tail}) do
    elements =
      tail
      |> pattern_shapes()
      |> contents()
      |> ShapeSet.union(pattern_shapes(head))

    ShapeSet.new([{:list, elements}])
  end

  defp pattern_shapes(%IR.ListType{data: data}) do
    elements =
      data
      |> Enum.map(&pattern_shapes/1)
      |> ShapeSet.union_all()

    ShapeSet.new([{:list, elements}])
  end

  defp pattern_shapes(%IR.MapType{data: data}) do
    ShapeSet.new([map_shape(data, &pattern_shapes/1)])
  end

  defp pattern_shapes(%IR.MatchOperator{left: left, right: right}) do
    ShapeSet.union_all([pattern_shapes(left), pattern_shapes(right)])
  end

  defp pattern_shapes(%IR.TupleType{data: data}) do
    ShapeSet.new([{:tuple, Enum.map(data, &pattern_shapes/1)}])
  end

  defp pattern_shapes(%type{}) when type in @primitive_types, do: ShapeSet.new([:prim])

  defp pattern_shapes(_pattern), do: ShapeSet.new()

  # The variables a pattern binds, a pinned one being read, not bound.
  defp pattern_variables(%IR.PinOperator{}, vars), do: vars

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

  # The summary with the arguments put in for its params (see apply_summary/2). With a ctx, the
  # dynamic calls and dots on a module an argument makes known are made too.
  defp put_args(summary, args, ctx) do
    summary
    |> replace(&replace_param(&1, args), new_rep(ctx))
    |> widen()
  end

  defp put_binding(acc, var, binding) do
    %{acc | bindings: Map.update(acc.bindings, var, [binding], &[binding | &1])}
  end

  # Adds what the pattern names to the variable's shapes, when it names a type (see the contract).
  defp put_extras(acc, var, pattern) do
    if names_type?(pattern) do
      shapes = pattern_shapes(pattern)
      %{acc | extras: Map.update(acc.extras, var, shapes, &ShapeSet.union(&1, shapes))}
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

  defp put_side_extras(acc, %IR.Variable{name: name, version: version}, pattern) do
    put_extras(acc, {name, version}, pattern)
  end

  defp put_side_extras(acc, _side, _pattern), do: acc

  # A variable matched as a whole against a pattern (a case condition, the right side of a match, a
  # with clause's expression) takes what the pattern names.
  defp put_subject_extras(acc, subject_expr, pattern) do
    put_side_extras(acc, subject_expr, pattern)
  end

  # Adds the types the shapes hold to the accumulator (see types/2).
  defp put_types(shapes, acc, module_info_plt) when is_list(shapes) do
    ShapeSet.reduce(shapes, acc, &put_types(&1, &2, module_info_plt))
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

  defp put_types({kind, shapes}, acc, module_info_plt) when kind in [:as_map, :contents, :part] do
    put_types(shapes, acc, module_info_plt)
  end

  defp put_types({:dot, shapes, _name}, acc, module_info_plt) do
    put_types(shapes, acc, module_info_plt)
  end

  defp put_types({:dyn, module, _name, _arity, args}, acc, module_info_plt) do
    Enum.reduce([module | args], acc, &put_types(&1, &2, module_info_plt))
  end

  # A primitive, a param or an anonymous function's argument.
  defp put_types(_shape, acc, _module_info_plt), do: acc

  # The dispatch types and the component modules that values of the given shapes bring to the client
  # (see server_callback_analysis/3): the structs and components they hold, and what the graph walk
  # from the vertices the rule before this module applies from, and from the structs, finds.
  defp reaching_types(shapes, graph, flow) do
    %{modules: modules, reach: reach, structs: structs} = types(shapes, flow)
    module_info_plt = flow.module_info_plt

    walked_vertices =
      Digraph.reachable(graph, MapSet.to_list(MapSet.union(reach, structs)),
        opaque_vertex?: &CallGraph.protocol_function_mfa?(&1, module_info_plt)
      )

    components =
      modules
      |> Enum.concat(Enum.filter(walked_vertices, &is_atom/1))
      |> Enum.filter(&component?(&1, module_info_plt))
      |> Enum.uniq()
      |> Enum.sort()

    dispatch_types =
      walked_vertices
      |> CallGraph.protocol_dispatch_types(module_info_plt)
      |> MapSet.union(structs)

    {dispatch_types, components}
  end

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

  # How deep the function whose evaluation reads an answer is: nil in an entry, below every function.
  defp reader_depth(%{node: nil}), do: -1

  defp reader_depth(ctx) do
    [{_key, depth}] = :ets.lookup(ctx.memo, {:depth, ctx.node})
    depth
  end

  # Replaces, at any depth, each shape the replacer gives shapes for (it gives nil for a shape it
  # leaves as it is), and makes the calls that the replacing resolves: a call of an anonymous
  # function, and, when rep holds a ctx, a dynamic call or a dot whose module became known (see
  # call_dyn/5 and dot/3). rep also holds the counter of the calls of anonymous functions the
  # substitution made, in all its branches (see new_rep/1 and call_fun/3).
  defp replace(shapes, replacer, rep) do
    ShapeSet.flat_map(shapes, &replace_shape(&1, replacer, rep))
  end

  defp replace_arg({:arg, ref, index}, ref, args), do: Enum.at(args, index, ShapeSet.new())

  defp replace_arg(_shape, _ref, _args), do: nil

  defp replace_param({:param, index}, args), do: Enum.at(args, index, ShapeSet.new())

  defp replace_param(_shape, _args), do: nil

  defp replace_parts({:struct, module, fields}, replacer, rep) do
    ShapeSet.new([{:struct, module, replace(fields, replacer, rep)}])
  end

  defp replace_parts({kind, inner}, replacer, rep) when kind in [:bag, :list, :map] do
    ShapeSet.new([{kind, replace(inner, replacer, rep)}])
  end

  defp replace_parts({:tuple, elements}, replacer, rep) do
    ShapeSet.new([{:tuple, Enum.map(elements, &replace(&1, replacer, rep))}])
  end

  defp replace_parts({:fun, ref, returned}, replacer, rep) do
    ShapeSet.new([{:fun, ref, replace(returned, replacer, rep)}])
  end

  defp replace_parts({:call, fun, args}, replacer, rep) do
    new_args = Enum.map(args, &replace(&1, replacer, rep))

    fun
    |> replace(replacer, rep)
    |> apply_fun(new_args, rep)
  end

  defp replace_parts({:as_map, shapes}, replacer, rep) do
    shapes
    |> replace(replacer, rep)
    |> as_maps()
  end

  defp replace_parts({:contents, shapes}, replacer, rep) do
    shapes
    |> replace(replacer, rep)
    |> contents()
  end

  defp replace_parts({:part, shapes}, replacer, rep) do
    shapes
    |> replace(replacer, rep)
    |> parts()
  end

  defp replace_parts({:dot, shapes, name}, replacer, rep) do
    new_shapes = replace(shapes, replacer, rep)

    if rep.ctx do
      dot(new_shapes, name, rep.ctx)
    else
      ShapeSet.new([{:dot, new_shapes, name}])
    end
  end

  defp replace_parts({:dyn, module, name, arity, args}, replacer, rep) do
    new_module = replace(module, replacer, rep)
    new_args = Enum.map(args, &replace(&1, replacer, rep))

    if rep.ctx do
      call_dyn(new_module, name, arity, new_args, rep.ctx)
    else
      ShapeSet.new([{:dyn, new_module, name, arity, new_args}])
    end
  end

  # An atom, a primitive, a param, an anonymous function's argument, or the rule before this module
  # applied from a vertex, which holds none of them.
  defp replace_parts(shape, _replacer, _rep), do: ShapeSet.new([shape])

  defp replace_shape(shape, replacer, rep) do
    case replacer.(shape) do
      nil -> replace_parts(shape, replacer, rep)
      replaced -> replaced
    end
  end

  # The params and anonymous function arguments the shapes start from, when every alternative is one
  # of them or a step of only them (see collapse_route/1); :error otherwise.
  defp route_roots(shapes) do
    ShapeSet.reduce(shapes, {:ok, ShapeSet.new()}, fn
      _shape, :error -> :error
      {:param, _index} = root, {:ok, roots} -> {:ok, ShapeSet.put(roots, root)}
      {:arg, _ref, _index} = root, {:ok, roots} -> {:ok, ShapeSet.put(roots, root)}
      {step, inner}, {:ok, roots} when step in @route_steps -> route_step_roots(inner, roots)
      _other, {:ok, _roots} -> :error
    end)
  end

  defp route_step?({step, _inner}) when step in @route_steps, do: true

  defp route_step?(_shape), do: false

  defp route_step_roots(inner, roots) do
    case route_roots(inner) do
      {:ok, inner_roots} -> {:ok, ShapeSet.union(roots, inner_roots)}
      :error -> :error
    end
  end

  # Runs a public entry with the tables of a solve (see solve/1), given in the ctx: `answers` holds
  # `{mfa, answer}` for the functions the run is solving; `dependents` holds `{callee, caller}` when the
  # caller's evaluation read the callee's answer (a bag, so each pair once); `work` holds
  # `{{-depth, sequence}, mfa}`, the functions to evaluate (see solve/1); `memo` holds the
  # variables' shapes once read (see read_variable/2), `{:queued, mfa}`, `{:depth, mfa}`, `{:evaluations, mfa}`,
  # `:sequence` and `:unsettled`. `ctx.mfa` is the function whose code is read, and `ctx.node` the
  # function the solver evaluates, nil in the entry itself. Forgets the modules' functions it read
  # (see module_functions/2) when done. An entry never runs inside another one.
  defp run(flow, fun) do
    ctx = %{
      answers: :ets.new(__MODULE__, [:set, :private]),
      dependents: :ets.new(__MODULE__, [:bag, :private]),
      flow: flow,
      frames: [],
      memo: :ets.new(__MODULE__, [:set, :private]),
      mfa: nil,
      node: nil,
      work: :ets.new(__MODULE__, [:ordered_set, :private])
    }

    try do
      fun.(ctx)
    after
      Enum.each([ctx.answers, ctx.dependents, ctx.memo, ctx.work], &:ets.delete/1)

      for {{__MODULE__, :functions, _module} = key, _functions} <- Process.get() do
        Process.delete(key)
      end
    end
  end

  # Runs the entry's function and returns what it gives; when it read an answer that is not final,
  # solves the work list first and runs it again, until a run reads only final answers. The function
  # makes its own frames, so that each run reads its variables again.
  defp settle(ctx, fun) do
    :ets.insert(ctx.memo, {:unsettled, false})
    result = fun.()

    if :ets.lookup_element(ctx.memo, :unsettled, 2) do
      solve(ctx)
      settle(ctx, fun)
    else
      result
    end
  end

  defp shape_contents({:atom, _atom}), do: ShapeSet.new()

  defp shape_contents(:prim), do: ShapeSet.new([:prim])

  defp shape_contents({:struct, _module, fields}), do: fields

  defp shape_contents({:tuple, elements}), do: ShapeSet.union_all(elements)

  defp shape_contents({kind, inner}) when kind in [:bag, :list, :map], do: inner

  defp shape_contents(shape) when elem(shape, 0) in @pending_kinds do
    ShapeSet.new([{:contents, ShapeSet.new([shape])}])
  end

  # The rule before this module applied from a vertex holds itself; a function holds nothing to
  # take apart.
  defp shape_contents({:reach, _vertex} = reach), do: ShapeSet.new([reach])

  defp shape_contents({:fun, _ref, _returned}), do: ShapeSet.new()

  defp shape_leaves({:struct, module, fields}) do
    field_leaves =
      fields
      |> leaves()
      |> ShapeSet.to_list()

    [{:struct, module, ShapeSet.new()} | field_leaves]
  end

  defp shape_leaves({kind, inner}) when kind in [:bag, :list, :map] do
    inner
    |> leaves()
    |> ShapeSet.to_list()
  end

  defp shape_leaves({:tuple, elements}) do
    elements
    |> ShapeSet.union_all()
    |> leaves()
    |> ShapeSet.to_list()
  end

  defp shape_leaves({:fun, _ref, returned}) do
    returned
    |> leaves()
    |> ShapeSet.to_list()
  end

  defp shape_leaves({:call, fun, args}) do
    [fun | args]
    |> Enum.map(&leaves/1)
    |> ShapeSet.union_all()
    |> ShapeSet.to_list()
  end

  defp shape_leaves({:dot, shapes, name}), do: [{:dot, leaves(shapes), name}]

  defp shape_leaves({:dyn, module, name, arity, args}) do
    [{:dyn, leaves(module), name, arity, Enum.map(args, &bag_of_leaves/1)}]
  end

  defp shape_leaves({kind, shapes}) when kind in [:as_map, :contents, :part] do
    [{kind, leaves(shapes)}]
  end

  # An atom, a primitive, a param, an anonymous function's argument, or the rule before this module
  # applied from a vertex.
  defp shape_leaves(shape), do: [shape]

  defp shape_parts(shape) when is_tuple(shape) and elem(shape, 0) in @pending_kinds do
    ShapeSet.new([{:part, ShapeSet.new([shape])}])
  end

  defp shape_parts({:atom, _atom}), do: ShapeSet.new()

  defp shape_parts({:fun, _ref, _returned}), do: ShapeSet.new()

  defp shape_parts(shape) when is_tuple(shape) and elem(shape, 0) in @data_kinds do
    ShapeSet.new([{:bag, nested_shapes(shape)}])
  end

  # A value of unknown structure, the rule before this module from a vertex, or a primitive.
  defp shape_parts(shape), do: ShapeSet.new([shape])

  # Evaluates the functions of the work list until it is empty (see evaluate/2): the deepest first, a
  # function met while evaluating another one being one deeper, and among equals in the order they were
  # put there. The deepest first answers the functions a function calls before the function is
  # evaluated again, so a caller is not evaluated once for every change of a callee still settling
  # (which made callers reach @evaluations_before_top on their own); in the order they were put there,
  # the functions of a loop are each evaluated once per sweep (the latest first evaluated a ring of four
  # functions 38 times, against 18).
  # Then every answer the run holds is final: none changed since the evaluations that read it. They go
  # to the analysis, kept for the rest of the compile.
  defp solve(ctx) do
    case :ets.first(ctx.work) do
      :"$end_of_table" ->
        for {mfa, answer} <- :ets.tab2list(ctx.answers) do
          PLT.put(ctx.flow.summaries, mfa, answer)
        end

        :ets.delete_all_objects(ctx.answers)
        :ets.delete_all_objects(ctx.dependents)
        :ok

      key ->
        [{^key, mfa}] = :ets.take(ctx.work, key)
        :ets.delete(ctx.memo, {:queued, mfa})
        evaluate(mfa, ctx)
        solve(ctx)
    end
  end

  # The current answer of a function the run is solving; the evaluation reading it is made again when
  # it changes (see evaluate/2). A function met for the first time answers nothing until it is
  # evaluated. A function with no IR, or a protocol function, gives everything it is given (see the
  # contract): which implementation runs depends on the type of a value, and following every one
  # would follow code the value never meets.
  defp solving_summary({_module, _function, arity} = mfa, ctx) do
    if function_clauses(mfa, ctx) == nil or
         CallGraph.protocol_function_mfa?(mfa, ctx.flow.module_info_plt) do
      ShapeSet.new([{:bag, params(arity)}])
    else
      if ctx.node, do: :ets.insert(ctx.dependents, {mfa, ctx.node})
      :ets.insert(ctx.memo, {:unsettled, true})

      case :ets.lookup(ctx.answers, mfa) do
        [{^mfa, answer}] ->
          answer

        [] ->
          :ets.insert(ctx.answers, {mfa, ShapeSet.new()})
          :ets.insert(ctx.memo, {{:depth, mfa}, reader_depth(ctx) + 1})
          enqueue(mfa, ctx)
          ShapeSet.new()
      end
    end
  end

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
    |> Enum.all?(fn {element, pattern} -> ShapeSet.any?(element, &may_match?(&1, pattern)) end)
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

  defp structurally_may_match?(:prim, _pattern), do: true

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

  defp subject_shapes({:arg, _ref, _index} = arg, _ctx), do: ShapeSet.new([arg])

  defp subject_shapes({:param, index}, _ctx), do: ShapeSet.new([{:param, index}])

  # A rescue without modules takes any exception, raised anywhere the function reaches: a struct.
  defp subject_shapes({:rescue, []}, ctx), do: ShapeSet.new([{:as_map, top(ctx.mfa)}])

  # An exception raised where the function reaches, of one of the modules, holding anything.
  defp subject_shapes({:rescue, modules}, ctx) do
    fields = top(ctx.mfa)

    modules
    |> Enum.map(&{:struct, &1, fields})
    |> ShapeSet.new()
  end

  defp subject_shapes(:top, ctx), do: top(ctx.mfa)

  # The summary of the function with the given arguments put in.
  defp summary_with_args(mfa, args, ctx) do
    mfa
    |> callee_summary(ctx)
    |> put_args(args, ctx)
  end

  defp variable_shapes(frame, var, ctx) do
    frame.bindings
    |> Map.get(var, [])
    |> Enum.map(fn {pattern, subject} -> extract(subject_shapes(subject, ctx), pattern, var) end)
    |> ShapeSet.union_all()
    |> ShapeSet.union(Map.get(frame.extras, var, ShapeSet.new()))
  end

  # Keeps the given shapes from growing without end: a set nested @max_depth deep that holds shapes
  # with more shapes inside, or a set holding more than @max_alternatives alternatives, becomes a bag
  # of its leaves (see leaves/1), which holds the same types. A recursive function whose answer
  # nests deeper on every pass then settles. A set of leaves stays as it is: an empty one is no value
  # at all (a branch that never returns), which a bag is not.
  defp widen(shapes) do
    shapes
    |> collapse_routes()
    |> widen(0)
  end

  defp widen(shapes, depth) do
    cond do
      ShapeSet.size(shapes) > @max_alternatives -> ShapeSet.new([{:bag, leaves(shapes)}])
      depth < @max_depth -> ShapeSet.map(shapes, &widen_shape(&1, depth + 1))
      ShapeSet.all?(shapes, &(shape_leaves(&1) == [&1])) -> shapes
      true -> ShapeSet.new([{:bag, leaves(shapes)}])
    end
  end

  defp widen_shape({:struct, module, fields}, depth), do: {:struct, module, widen(fields, depth)}

  defp widen_shape({kind, inner}, depth) when kind in [:as_map, :contents, :list, :map, :part] do
    {kind, widen(inner, depth)}
  end

  defp widen_shape({:bag, inner}, _depth), do: {:bag, leaves(inner)}

  defp widen_shape({:tuple, elements}, depth), do: {:tuple, Enum.map(elements, &widen(&1, depth))}

  defp widen_shape({:fun, ref, returned}, depth), do: {:fun, ref, widen(returned, depth)}

  defp widen_shape({:call, fun, args}, depth) do
    {:call, widen(fun, depth), Enum.map(args, &widen(&1, depth))}
  end

  defp widen_shape({:dot, shapes, name}, depth), do: {:dot, widen(shapes, depth), name}

  defp widen_shape({:dyn, module, name, arity, args}, depth) do
    {:dyn, widen(module, depth), name, arity, Enum.map(args, &widen(&1, depth))}
  end

  # An atom, a primitive, a param, an anonymous function's argument, or the rule before this module
  # applied from a vertex.
  defp widen_shape(shape, _depth), do: shape

  defp with_nested_shapes(shapes) do
    ShapeSet.flat_map(shapes, &ShapeSet.new([&1 | nested_shape_list(&1)]))
  end
end
