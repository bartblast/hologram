defmodule Hologram.Entity.Expression do
  @moduledoc false

  # Lowers what a relationship line was written with to the data form its declaration stores. Two
  # options name entity vocabulary: inverse: the relationship a reversing declaration reverses,
  # sort: the attributes its rows are ordered by. Both name what the related type declares - the
  # type the line points at, the way a stage's bare names are its source's rows - so both take
  # bare names, and anything from the surrounding code is pinned with ^. Every other option is a
  # plain value and is left as written.
  #
  # It runs at expansion and judges the spelling only. Whether the related type declares what the
  # two options name cannot be judged here, since that type may not be compiled while the
  # declaring module's body is executing.

  alias Hologram.Query.Expression, as: QueryExpression

  @inverse_names %{
    stage: "inverse",
    names: "the relationship it reverses",
    spelled: "a bare name"
  }

  @written_in_place_keys [:inverse, :sort]

  @doc """
  Lowers the options argument of a `relationship` line to the AST of the keyword list its
  declaration stores.

  `inverse:` lowers a bare name to an atom (`inverse: channel` to `inverse: :channel`). `sort:`
  lowers a bare attribute name to an atom and a list of names and `{name, direction}` pairs to the
  list of atoms and pairs, keyword syntax included (`sort: created_at` to `sort: :created_at`,
  `sort: [title, priority: :desc]` to `sort: [:title, priority: :desc]`). A pinned value of
  either, or a pinned direction, lowers to the expression. Every other entry passes through
  unchanged.

  Options not written as a list in place pass through too, wrapped in a check that runs where the
  module body does: they may not hold `inverse:` or `sort:`, whose names are written on the line.

  Raises Hologram.CompileError, located at the offending node, on an atom or `__MODULE__` where a
  bare name goes (naming the bare spelling for an atom) and on anything else in a name position.
  """
  @spec relationship_opts(Macro.t(), Macro.Env.t()) :: Macro.t()
  def relationship_opts(opts, env) when is_list(opts) do
    Enum.map(opts, &option(&1, env))
  end

  def relationship_opts(opts, _env) do
    quote do
      Hologram.Entity.Expression.validate_unlowered_opts!(unquote(opts))
    end
  end

  @doc """
  Returns the given relationship options, evaluated from an expression rather than written as a
  list in place.

  Raises Hologram.CompileError when they hold `inverse:` or `sort:`.
  """
  @spec validate_unlowered_opts!(any) :: any
  def validate_unlowered_opts!(opts) do
    if is_list(opts) and Enum.any?(opts, &written_in_place_entry?/1) do
      raise Hologram.CompileError,
        message:
          "relationship options with inverse: or sort: are written in place on the line, got: #{inspect(opts)}"
    end

    opts
  end

  defp option({:inverse, {:__MODULE__, _meta, context} = value}, env) when is_atom(context) do
    QueryExpression.compile_error!(
      "inverse names the relationship it reverses with a bare name, or with a pinned expression when the name comes from the surrounding code, got: __MODULE__",
      value,
      env
    )
  end

  defp option({:inverse, value}, env) do
    {:inverse, QueryExpression.name!(value, @inverse_names, env)}
  end

  defp option({:sort, value}, env), do: {:sort, QueryExpression.ordering(value, env)}

  defp option(entry, _env), do: entry

  defp written_in_place_entry?({key, _value}), do: key in @written_in_place_keys

  defp written_in_place_entry?(_entry), do: false
end
