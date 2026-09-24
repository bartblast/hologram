defmodule Hologram.Compiler.DynamicCallSites do
  @moduledoc false

  # Finds the dynamic calls the compiler tracks: calls of a reflection function on a module the code
  # does not name, such as `mod.__changeset__()` or `data.__struct__`. The reflection functions are
  # Ecto's schema reflection, __changeset__/0 and __schema__/1,2, and a struct's __struct__/0,1 (see
  # reflection_functions/0); this has nothing to do with Hologram.Reflection. A call on a named
  # module needs no tracking: it gives the call graph an edge to the function it calls. Not every
  # dynamic call is tracked: a call whose function name is known only at runtime (`apply(mod, fun,
  # args)` with a variable `fun`, `:erlang.make_fun/3`) is not, since the call graph adds no edge for
  # such calls and no function reached only that way is bundled, reflection functions included.

  alias Hologram.Compiler.IR

  @reflection_functions [
    {:__changeset__, 0},
    {:__schema__, 1},
    {:__schema__, 2},
    {:__struct__, 0},
    {:__struct__, 1}
  ]

  @names [:__changeset__, :__schema__, :__struct__]

  # What an argument of a call is: an atom written in the code, the calling clause's parameter at
  # the given index, or anything else.
  @type arg_kind :: :literal | {:param, non_neg_integer} | :other

  # The module a site calls the function on: the function's parameter at the given index, or
  # anything else.
  @type kind :: :open | {:param, non_neg_integer}

  @type site :: {atom, arity, kind}

  @doc """
  Lists the calls of the given function in the given clause of a function of the given module, one
  list per call, holding each argument's kind and IR. A call is a remote call with the callee's
  module written in the code, a local call when the callee is a function of the clause's module, or
  an apply/3 with the module, the function and the argument list written out. An argument is
  `:literal` when it is an atom written in the code, `{:param, index}` when it is the clause's
  parameter at that index, and `:other` otherwise. A call in an anonymous function keeps its
  arguments' kinds, since a closure sees the value its enclosing function was given.
  """
  @spec call_args(IR.FunctionClause.t(), module, mfa) :: [[{arg_kind, IR.t()}]]
  def call_args(%IR.FunctionClause{params: params, guards: guards, body: body}, module, callee) do
    [guards, body]
    |> collect_calls(module, callee, [])
    |> Enum.reverse()
    |> Enum.map(fn args -> Enum.map(args, &{arg_kind(&1, params), &1}) end)
  end

  @doc """
  Returns the reflection functions, as `{name, arity}` tuples.
  """
  @spec reflection_functions :: [{atom, arity}]
  def reflection_functions, do: @reflection_functions

  @doc """
  Lists the calls of reflection functions on a module the code does not name in the given function
  clause, each once, sorted. The kind of a call is `{:param, index}` when the module is the clause's
  parameter at that index, and `:open` otherwise. A call in an anonymous function keeps the kind,
  since a closure sees the value its enclosing function was given. The dot without parentheses
  counts as a call when the name is one of a zero-arity reflection function: the client runs
  `data.__struct__` as a call when `data` is a module.
  """
  @spec list(IR.FunctionClause.t()) :: [site]
  def list(%IR.FunctionClause{params: params, guards: guards, body: body}) do
    [guards, body]
    |> collect_sites(params, [])
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp add_site(sites, function, arity, module, params) do
    if {function, arity} in @reflection_functions do
      [{function, arity, kind(module, params)} | sites]
    else
      sites
    end
  end

  # An apply with an argument list written out calls the function with that many arguments; with
  # any other argument list, it can call the function with any arity it has.
  defp apply_arities(function, %IR.ListType{data: args}) do
    if {function, length(args)} in @reflection_functions, do: [length(args)], else: []
  end

  defp apply_arities(function, _args) do
    for {^function, arity} <- @reflection_functions, do: arity
  end

  defp arg_kind(%IR.AtomType{}, _params), do: :literal

  defp arg_kind(arg, params) do
    case param_index(arg, params) do
      nil -> :other
      index -> {:param, index}
    end
  end

  # The argument lists of the calls of the callee, the last found first.
  defp collect_calls(
         %IR.RemoteFunctionCall{
           module: %IR.AtomType{value: :erlang},
           function: :apply,
           args: [
             %IR.AtomType{value: module},
             %IR.AtomType{value: function},
             %IR.ListType{data: args}
           ]
         } = ir,
         clause_module,
         {module, function, arity} = callee,
         calls
       )
       when length(args) == arity do
    collect_calls(Map.from_struct(ir), clause_module, callee, [args | calls])
  end

  defp collect_calls(
         %IR.RemoteFunctionCall{
           module: %IR.AtomType{value: module},
           function: function,
           args: args
         } = ir,
         clause_module,
         {module, function, arity} = callee,
         calls
       )
       when length(args) == arity do
    collect_calls(Map.from_struct(ir), clause_module, callee, [args | calls])
  end

  defp collect_calls(
         %IR.LocalFunctionCall{function: function, args: args} = ir,
         module,
         {module, function, arity} = callee,
         calls
       )
       when length(args) == arity do
    collect_calls(Map.from_struct(ir), module, callee, [args | calls])
  end

  defp collect_calls(%_struct{} = ir, clause_module, callee, calls) do
    ir
    |> Map.from_struct()
    |> Map.values()
    |> collect_calls(clause_module, callee, calls)
  end

  defp collect_calls(list, clause_module, callee, calls) when is_list(list) do
    Enum.reduce(list, calls, &collect_calls(&1, clause_module, callee, &2))
  end

  defp collect_calls(map, clause_module, callee, calls) when is_map(map) do
    map
    |> Map.to_list()
    |> collect_calls(clause_module, callee, calls)
  end

  defp collect_calls(tuple, clause_module, callee, calls) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> collect_calls(clause_module, callee, calls)
  end

  defp collect_calls(_ir, _clause_module, _callee, calls), do: calls

  defp collect_sites(
         %IR.DotOperator{left: left, right: %IR.AtomType{value: function}},
         params,
         sites
       )
       when function in @names do
    new_sites =
      if match?(%IR.AtomType{}, left), do: sites, else: add_site(sites, function, 0, left, params)

    collect_sites(left, params, new_sites)
  end

  defp collect_sites(
         %IR.RemoteFunctionCall{
           module: %IR.AtomType{value: :erlang},
           function: :apply,
           args: [module, %IR.AtomType{value: function}, args]
         },
         params,
         sites
       )
       when function in @names do
    new_sites =
      if match?(%IR.AtomType{}, module) do
        sites
      else
        function
        |> apply_arities(args)
        |> Enum.reduce(sites, &add_site(&2, function, &1, module, params))
      end

    collect_sites([module, args], params, new_sites)
  end

  defp collect_sites(
         %IR.RemoteFunctionCall{module: module, function: function, args: args},
         params,
         sites
       )
       when function in @names do
    new_sites =
      if match?(%IR.AtomType{}, module),
        do: sites,
        else: add_site(sites, function, length(args), module, params)

    collect_sites([module, args], params, new_sites)
  end

  defp collect_sites(%_struct{} = ir, params, sites) do
    ir
    |> Map.from_struct()
    |> Map.values()
    |> collect_sites(params, sites)
  end

  defp collect_sites(list, params, sites) when is_list(list) do
    Enum.reduce(list, sites, &collect_sites(&1, params, &2))
  end

  defp collect_sites(map, params, sites) when is_map(map) do
    map
    |> Map.to_list()
    |> collect_sites(params, sites)
  end

  defp collect_sites(tuple, params, sites) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> collect_sites(params, sites)
  end

  defp collect_sites(_ir, _params, sites), do: sites

  defp kind(module, params) do
    case param_index(module, params) do
      nil -> :open
      index -> {:param, index}
    end
  end

  # The index of the parameter the given expression is, or nil. IR read from a BEAM gives each
  # binding of a variable its own version, so a variable with a parameter's name and version is that
  # parameter's value. IR built from a code string has no versions, and such a variable is taken for
  # anything.
  defp param_index(%IR.Variable{version: nil}, _params), do: nil

  defp param_index(%IR.Variable{name: name, version: version}, params) do
    Enum.find_index(params, &match?(%IR.Variable{name: ^name, version: ^version}, &1))
  end

  defp param_index(_expr, _params), do: nil
end
