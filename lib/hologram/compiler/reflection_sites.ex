defmodule Hologram.Compiler.ReflectionSites do
  @moduledoc false

  # Finds the calls of reflection functions (__changeset__/0, __schema__/1, __schema__/2,
  # __struct__/0, __struct__/1) on a module the code does not name, such as `mod.__changeset__()`
  # or `data.__struct__`. A call on a named module gives the call graph an edge to the function it
  # calls, so only these calls can reach a reflection function the graph cannot see. A call whose
  # function name is known only at runtime (`apply(mod, fun, args)` with a variable `fun`,
  # `:erlang.make_fun/3`) is not one of them: the call graph adds no edge for such calls, so no
  # function reached only that way is bundled, reflection functions included.

  alias Hologram.Compiler.IR

  @functions [
    {:__changeset__, 0},
    {:__schema__, 1},
    {:__schema__, 2},
    {:__struct__, 0},
    {:__struct__, 1}
  ]

  @names [:__changeset__, :__schema__, :__struct__]

  # The module a site calls the function on: the function's parameter at the given index, or
  # anything else.
  @type kind :: :open | {:param, non_neg_integer}

  @type site :: {atom, arity, kind}

  @doc """
  Returns the reflection functions, as `{name, arity}` tuples.
  """
  @spec functions :: [{atom, arity}]
  def functions, do: @functions

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
    if {function, arity} in @functions do
      [{function, arity, kind(module, params)} | sites]
    else
      sites
    end
  end

  # An apply with an argument list written out calls the function with that many arguments; with
  # any other argument list, it can call the function with any arity it has.
  defp apply_arities(function, %IR.ListType{data: args}) do
    if {function, length(args)} in @functions, do: [length(args)], else: []
  end

  defp apply_arities(function, _args) do
    for {^function, arity} <- @functions, do: arity
  end

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

  # IR read from a BEAM gives each binding of a variable its own version, so a variable with a
  # parameter's name and version is that parameter's value. IR built from a code string has no
  # versions, and such a variable is taken for anything.
  defp kind(%IR.Variable{version: nil}, _params), do: :open

  defp kind(%IR.Variable{name: name, version: version}, params) do
    case Enum.find_index(params, &match?(%IR.Variable{name: ^name, version: ^version}, &1)) do
      nil -> :open
      index -> {:param, index}
    end
  end

  defp kind(_module, _params), do: :open
end
