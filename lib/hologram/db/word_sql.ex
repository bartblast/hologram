defmodule Hologram.DB.WordSQL do
  @moduledoc false

  # What each query word computes, in SQL, over operands already rendered. A word's meaning lives
  # here and in Hologram.Query.Words, and the two have to agree on every value.

  @doc """
  Returns the SQL picking the given position, counting from 0, of the given text split by the given
  separator, nil past the end, as `String.split/2` then `Enum.at/2` do.

  PostgreSQL splits an empty string into no parts where Elixir gives one empty part, so the text
  is split with the separator put before it, which always gives a first, empty part to skip, and
  the text goes into the SQL only once. The separator is a non-empty string, and the position goes
  in as a literal, since PostgreSQL's arrays count from 1.
  """
  @spec at_split(String.t(), String.t(), non_neg_integer) :: String.t()
  def at_split(text, separator, position) do
    "(string_to_array(#{separator} || (#{text}), #{separator}))[#{position + 2}]"
  end

  @doc """
  Returns the SQL of the first of the given values that isn't NULL.
  """
  @spec coalesce(list(String.t())) :: String.t()
  def coalesce(values), do: "COALESCE(#{Enum.join(values, ", ")})"

  @doc """
  Returns the SQL joining the given strings, NULL when any of them is.
  """
  @spec concat(list(String.t())) :: String.t()
  def concat(operands), do: "(#{Enum.join(operands, " || ")})"

  @doc """
  Returns the SQL counting the rows of the given source, a `FROM` clause through its `WHERE`.
  """
  @spec count(String.t()) :: String.t()
  def count(source), do: "(SELECT COUNT(*) #{source})"

  @doc """
  Returns the query counting the rows of the given source, a `FROM` clause through its `WHERE`, per
  value of the given key column, as `k` and `v`.
  """
  @spec count_by(String.t(), String.t()) :: String.t()
  def count_by(key, source), do: "SELECT #{key} AS k, COUNT(*) AS v #{source} GROUP BY #{key}"

  @doc """
  Returns the SQL of the value appearing most often among the given source's rows, a `FROM` clause
  through its `WHERE`, skipping NULL and NULL when none is left. A tie goes to the smallest value,
  by the given sort key column and then the value, or by the value alone given nil.

  Rows group by the value alone: an upgrade can change the key computed for a value, so rows
  written on either side of it hold one value under two keys, and they still count as one.
  """
  @spec most_common(String.t(), String.t() | nil, String.t()) :: String.t()
  def most_common(value, sort_key, source) do
    order = if sort_key, do: "MIN(#{sort_key}), #{value}", else: value

    "(SELECT #{value} #{source} AND #{value} IS NOT NULL " <>
      "GROUP BY #{value} ORDER BY COUNT(*) DESC, #{order} LIMIT 1)"
  end

  @doc """
  Returns the query giving, per value of the given key column, what `most_common/3` gives over the
  source's rows holding that key, as `k` and `v`. The source is a `FROM` clause through a `WHERE`
  that leaves out NULL values.
  """
  @spec most_common_by(String.t(), String.t(), String.t() | nil, String.t()) :: String.t()
  def most_common_by(key, value, sort_key, source) do
    {sort_select, order} = if sort_key, do: {", MIN(#{sort_key}) AS s", "s, v"}, else: {"", "v"}

    "SELECT DISTINCT ON (k) k, v FROM (SELECT #{key} AS k, #{value} AS v, COUNT(*) AS n" <>
      "#{sort_select} #{source} GROUP BY #{key}, #{value}) AS grouped " <>
      "ORDER BY k, n DESC, #{order}"
  end
end
