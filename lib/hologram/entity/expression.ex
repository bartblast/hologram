defmodule Hologram.Entity.Expression do
  @moduledoc false

  # Lowers what a relationship line or a unique key was written with to the data form its
  # declaration stores. Two relationship options name entity vocabulary: inverse: the relationship
  # a reversing declaration reverses, sort: the attributes its rows are ordered by. Both name what
  # the related type declares - the type the line points at, the way a stage's bare names are its
  # source's rows - so both take bare names. Every other option is a plain value and is left as
  # written. A unique key names fields of the declaring type, bare as everywhere an entity type
  # names one. Anything from the surrounding code is pinned with ^.
  #
  # It runs at expansion and judges the spelling only. Whether the related type declares what the
  # two options name cannot be judged here, since that type may not be compiled while the
  # declaring module's body is executing, and whether a key's fields are declared is judged once
  # the body is, since a key may name fields declared below it.

  alias Hologram.Query.Expression, as: QueryExpression

  @inverse_names %{
    stage: "inverse",
    names: "the relationship it reverses",
    spelled: "a bare name"
  }

  @unique_names %{stage: "unique", names: "a field", spelled: "a bare name"}

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
  bare name goes (naming the bare spelling for an atom), on a pinned bare name no variable of the
  surrounding code holds (naming the bare spelling), and on anything else in a name position.
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
  Lowers the argument of a `unique` line to the AST of the list of field names its declaration
  stores.

  A list of bare field names lowers to their atoms (`[workspace, slug]` to `[:workspace, :slug]`),
  a pinned element to the expression, and a pinned list to the expression. A nil key passes
  through for the declaration to refuse.

  Raises Hologram.CompileError, located at the offending node, on an atom or `__MODULE__` in the
  list (naming the bare spelling of an atom), on a pinned bare name no variable of the surrounding
  code holds, on anything else in the list, and on a key that is neither a list written in place
  nor pinned (naming the pin a variable lacks, or the option a single field is unique through).
  """
  @spec unique_fields(Macro.t(), Macro.Env.t()) :: Macro.t()
  def unique_fields(fields, env) when is_list(fields) do
    if improper_list?(fields), do: QueryExpression.improper_names_error!(fields, "unique", env)

    Enum.map(fields, fn
      {:__MODULE__, _meta, context} = ast when is_atom(context) ->
        QueryExpression.compile_error!(
          "unique names a field with a bare name, or with a pinned expression when the name comes from the surrounding code, got: __MODULE__",
          ast,
          env
        )

      field ->
        QueryExpression.name!(field, @unique_names, env)
    end)
  end

  def unique_fields(nil, _env), do: nil

  def unique_fields({:^, _meta, [expr]} = ast, env) do
    if bare_name?(expr) and not QueryExpression.pin_holds_value?(ast, env) do
      QueryExpression.compile_error!(
        "#{Macro.to_string(ast)} pins #{Macro.to_string(expr)}, which no variable holds here - unique names fields with bare names in a list, like unique [workspace, slug]",
        ast,
        env
      )
    end

    expr
  end

  def unique_fields(fields, env) do
    hint =
      cond do
        bare_name?(fields) and QueryExpression.pin_holds_value?({:^, [], [fields]}, env) ->
          " - write ^#{Macro.to_string(fields)}"

        bare_name?(fields) or name_atom?(fields) ->
          " - a single field is unique through its own option, unique: true on the attribute or the relationship"

        true ->
          ""
      end

    QueryExpression.compile_error!(
      "unique takes a list of fields written in place, or a pinned expression when the list comes from the surrounding code, got: #{Macro.to_string(fields)}#{hint}",
      fields,
      env
    )
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

  # A list written with a tail, `[title | rest]`, whose last element is the `|` node.
  defp improper_list?(list), do: match?({:|, _meta, [_last, _tail]}, List.last(list))

  defp bare_name?({:__MODULE__, _meta, _context}), do: false

  defp bare_name?({name, _meta, context}) when is_atom(name) and is_atom(context), do: true

  defp bare_name?(_ast), do: false

  defp name_atom?(atom), do: is_atom(atom) and atom not in [nil, true, false]

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
