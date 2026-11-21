defmodule Hologram.Query.Words do
  @moduledoc false

  # What each query word computes, in Elixir, over values already read. A word's meaning lives
  # here once, so everything that runs one agrees with the database. Its SQL is in
  # Hologram.DB.WordSQL.

  alias Hologram.Query.Ordering

  @doc """
  Returns the part of the given split at the given position, counting from 0, as `Enum.at/2` does:
  nil past the end, and nil for a nil list.
  """
  @spec at(list(String.t()) | nil, non_neg_integer) :: String.t() | nil
  def at(nil, _position), do: nil

  def at(parts, position), do: Enum.at(parts, position)

  @doc """
  Returns the first of the given values that isn't nil, or nil when all are. A false is a value.
  """
  @spec coalesce(list(any)) :: any
  def coalesce(values), do: Enum.find(values, &(not is_nil(&1)))

  @doc """
  Returns the given strings joined, or nil when any of them is nil.
  """
  @spec concat(list(String.t() | nil)) :: String.t() | nil
  def concat(values) do
    if Enum.any?(values, &is_nil/1), do: nil, else: Enum.join(values)
  end

  @doc """
  Returns how many rows the given set holds.
  """
  @spec count(list) :: non_neg_integer
  def count(rows), do: length(rows)

  @doc """
  Returns the value that appears most often among the given ones, skipping nil, or nil when none
  is left. A tie goes to the smallest value. Values group and order as `Ordering.compare/3` compares
  them, which is how the database's `GROUP BY` and `ORDER BY` treat them, an enum by the given
  ranks.
  """
  @spec most_common(list(any), %{atom => non_neg_integer} | nil) :: any
  def most_common(values, ranks \\ nil) do
    non_nil = Enum.reject(values, &is_nil/1)

    if non_nil == [] do
      nil
    else
      # Sorted ascending, so the first of the largest groups holds the smallest value.
      non_nil
      |> Enum.sort(&(Ordering.compare(&1, &2, ranks) != :gt))
      |> Enum.chunk_while([], &chunk_equal(&1, &2, ranks), &finish_chunk/1)
      |> Enum.max_by(&length/1)
      |> List.last()
    end
  end

  @doc """
  Returns the given text split by the given separator, as `String.split/2` does, or nil for nil.
  """
  @spec split(String.t() | nil, String.t()) :: list(String.t()) | nil
  def split(nil, _separator), do: nil

  def split(text, separator), do: String.split(text, separator)

  defp chunk_equal(value, [], _ranks), do: {:cont, [value]}

  defp chunk_equal(value, [head | _rest] = chunk, ranks) do
    if Ordering.compare(value, head, ranks) == :eq do
      {:cont, [value | chunk]}
    else
      {:cont, chunk, [value]}
    end
  end

  defp finish_chunk(chunk), do: {:cont, chunk, []}
end
