defmodule Hologram.Entity.DerivedExpression do
  @moduledoc false

  # Lowers the function of a derived field to the body its definition function runs. The function's
  # arguments name fields of the row, which has no values while the definition is built, so every
  # place the body reads one is rewritten to Hologram.Entity.Derived.field/2 - a stand-in that
  # becomes a query over the row's set, a name of the row in a condition, or a row to read further
  # through.
  #
  # Inside a query a bare name is the queried row's, so the rewrite reads the body in two modes: an
  # Elixir position (the body, a stage's source, a pinned expression) reads the arguments, a query
  # position (a stage's other arguments, outside a pin) is left to the Hologram.Query macros as
  # written.

  alias Hologram.Entity.Derived
  alias Hologram.Query.Expression

  # The query stages a derived body reads its rows with, by the number of arguments each takes.
  @stages [count: 1, filter: 2, include: 2, one: 1, skip: 2, sort: 2, take: 2]

  @doc """
  Lowers the given derived field's function to the names its head binds and the body its definition
  function runs: an argument read in the body becomes a `Hologram.Entity.Derived.field/2` call
  naming the field, a dot chain on one names the path, a pipe is unpiped, a module attribute an
  unquote fragment reading its value where the body is escaped with `unquote: true`, and an alias its
  module.
  """
  @spec function(Macro.t(), Macro.Env.t()) :: {list(atom), Macro.t()}
  def function({:fn, _meta, [{:->, _arrow_meta, [args, body]}]}, env) do
    names = Enum.map(args, fn {name, _meta, _context} -> name end)
    state = %{env: env, names: names}

    {names, elixir_position(body, state)}
  end

  @doc """
  Returns the stages a derived body may call, as the keyword list `import/2`'s `:only` takes.
  """
  @spec stages() :: keyword(pos_integer)
  def stages, do: @stages

  defp elixir_position({:|>, _meta, [left, right]}, state) do
    left
    |> Macro.pipe(right, 0)
    |> elixir_position(state)
  end

  # A module attribute is read where the declaration is evaluated, as a function body reads one where
  # the function is defined - the module body is expanded whole before any of it runs, so the value
  # is not there yet when this does. The fragment is unquoted when the body is escaped into the
  # declaration, so the read lands in the module body, and the value it reads into the body.
  defp elixir_position({:@, _meta, [{name, _name_meta, context}]} = ast, _state)
       when is_atom(name) and is_atom(context) do
    value_ast =
      quote do
        Macro.escape(unquote(ast))
      end

    {:unquote, [], [value_ast]}
  end

  defp elixir_position({:__aliases__, _meta, _segments} = ast, state) do
    Macro.expand(ast, state.env)
  end

  defp elixir_position({name, _meta, context} = ast, state)
       when is_atom(name) and is_atom(context) do
    if name in state.names, do: field_call([name], state), else: ast
  end

  defp elixir_position({{:., _dot_meta, [_left, _field]}, _meta, []} = ast, state) do
    case Expression.hops(ast) do
      [root | _rest] = path when is_atom(root) ->
        if root in state.names do
          field_call(path, state)
        else
          generic(ast, state)
        end

      nil ->
        generic(ast, state)
    end
  end

  defp elixir_position({stage, meta, [source | rest] = args}, state)
       when is_atom(stage) and is_list(args) do
    if {stage, length(args)} in @stages do
      {stage, meta, [elixir_position(source, state) | Enum.map(rest, &query_position(&1, state))]}
    else
      generic({stage, meta, args}, state)
    end
  end

  defp elixir_position(ast, state), do: generic(ast, state)

  defp field_call(path, state) do
    quote do
      Derived.field(unquote(state.env.module), unquote(path))
    end
  end

  defp generic({head, meta, args}, state) when is_list(args) do
    {elixir_position(head, state), meta, Enum.map(args, &elixir_position(&1, state))}
  end

  defp generic({left, right}, state) do
    {elixir_position(left, state), elixir_position(right, state)}
  end

  defp generic(list, state) when is_list(list), do: Enum.map(list, &elixir_position(&1, state))

  defp generic(ast, _state), do: ast

  defp query_position({:^, meta, [expr]}, state), do: {:^, meta, [elixir_position(expr, state)]}

  defp query_position({:__aliases__, _meta, _segments} = ast, state) do
    Macro.expand(ast, state.env)
  end

  defp query_position({head, meta, args}, state) when is_list(args) do
    {query_position(head, state), meta, Enum.map(args, &query_position(&1, state))}
  end

  defp query_position({left, right}, state) do
    {query_position(left, state), query_position(right, state)}
  end

  defp query_position(list, state) when is_list(list),
    do: Enum.map(list, &query_position(&1, state))

  defp query_position(ast, _state), do: ast
end
