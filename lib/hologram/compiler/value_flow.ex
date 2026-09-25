defmodule Hologram.Compiler.ValueFlow do
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
  #      the types the code names for it, as before this module.

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.IR

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

  @doc """
  Returns the shapes of the value the given expression gives, where the expression is in the given
  clause of the given function.
  """
  @spec shapes(IR.t(), IR.FunctionClause.t(), mfa, t) :: shapes
  def shapes(expr, _clause, mfa, flow) do
    eval(expr, %{flow: flow, mfa: mfa})
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
  Returns what the given function's value is when the analysis cannot follow it: the rule before
  this module applied from the function, and everything the function is given.
  """
  @spec top(mfa) :: shapes
  def top({_module, _function, arity} = mfa) do
    params = for index <- 0..(arity - 1)//1, do: {:param, index}
    MapSet.new([{:reach, mfa} | params])
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

  defp eval(%IR.MapType{data: data}, ctx) do
    case List.keytake(data, %IR.AtomType{value: :__struct__}, 0) do
      {{_key, %IR.AtomType{value: module}}, fields} ->
        MapSet.new([{:struct, module, eval_pairs(fields, ctx)}])

      _no_struct_key ->
        MapSet.new([{:map, eval_pairs(data, ctx)}])
    end
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

  defp eval(%IR.TupleType{data: data}, ctx) do
    MapSet.new([{:tuple, Enum.map(data, &eval(&1, ctx))}])
  end

  defp eval(%type{}, _ctx) when type in @primitive_types, do: MapSet.new([:prim])

  defp eval(_expr, ctx), do: top(ctx.mfa)

  defp eval_all(exprs, ctx) do
    exprs
    |> Enum.map(&eval(&1, ctx))
    |> union()
  end

  defp eval_pairs(pairs, ctx) do
    pairs
    |> Enum.flat_map(fn {key, value} -> [key, value] end)
    |> eval_all(ctx)
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

  defp union(sets), do: Enum.reduce(sets, MapSet.new(), &MapSet.union/2)
end
