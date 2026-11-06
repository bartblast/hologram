defmodule Hologram.Query.Ordering do
  @moduledoc false

  # How the query kernel orders values and rows over plain Elixir data, the way the database orders
  # them: what a comparison in a filter and a query's sort agree on, kept in one place so every
  # evaluation over rows read into memory orders them alike.

  alias Hologram.DB.SortKey

  @doc """
  Compares two values of one kind the way the database orders them, as `:lt`, `:eq` or `:gt`: a
  date, a datetime or a time chronologically, a string by the key derived from it and then by
  itself, and an enum value by its position in the given ranks, a map from each declared value to
  its index. Given no ranks, an enum value compares as any other atom.
  """
  @spec compare(any, any, %{atom => non_neg_integer} | nil) :: :eq | :gt | :lt
  def compare(left, right, ranks \\ nil)

  # Strings order by the key derived from them and then by themselves, which is the pair of
  # columns the database orders them by - the key carries the practical order, and the value
  # behind it settles what the key cannot, since the key is a bounded prefix of it.
  def compare(left, right, nil) when is_binary(left) and is_binary(right) do
    case compare_values(SortKey.compute(left), SortKey.compute(right)) do
      :eq -> compare_values(left, right)
      result -> result
    end
  end

  def compare(left, right, nil), do: compare_values(left, right)

  # An enum value orders by its position in the declared list, which is the order the database
  # holds the type in - so what compares is the pair of positions rather than the labels. A value
  # the list does not hold is a bug surfacing rather than a case to place: the database refuses
  # to store one, and the lookup raises on it here.
  def compare(left, right, ranks) do
    compare_values(Map.fetch!(ranks, left), Map.fetch!(ranks, right))
  end

  @doc """
  Returns the ranks of the enum fields among the given names of the given entity type - attributes
  and derived fields holding an enum - keyed by name, each a map from a declared value to its
  index.
  """
  @spec enum_ranks(module, list(atom)) :: %{atom => %{atom => non_neg_integer}}
  def enum_ranks(entity_type, names) do
    entity_type.__attributes__()
    |> Enum.concat(entity_type.__derived__())
    |> Enum.filter(fn {name, type, _opts} -> type == :enum and name in names end)
    |> Map.new(fn {name, _type, opts} ->
      ranks =
        opts
        |> Keyword.fetch!(:values)
        |> Enum.with_index()
        |> Map.new()

      {name, ranks}
    end)
  end

  @doc """
  Returns the given rows of the given entity type ordered by the given sort keys, `{name,
  direction}` pairs, each row's keys read once with the given function of a row and a name. Values
  compare as `compare/3` compares them - an enum key, a derived one included, by its position among
  the type's declared values - and a missing value goes last ascending and first descending. Rows
  tying on every key keep no particular order, so a total order needs a unique key among them, as
  a normalized query's sort has its id.
  """
  @spec sort(list(struct), list({atom, :asc | :desc}), module, (struct, atom -> any)) ::
          list(struct)
  def sort(rows, keys, entity_type, read) do
    names = Enum.map(keys, fn {name, _direction} -> name end)
    ranks = enum_ranks(entity_type, names)

    rows
    |> Enum.map(fn row -> {row, Enum.map(names, &read.(row, &1))} end)
    |> Enum.sort(fn {_left, left_values}, {_right, right_values} ->
      precedes?(left_values, right_values, keys, ranks)
    end)
    |> Enum.map(fn {row, _values} -> row end)
  end

  # Missing values are placed the way the database places them - last when ascending, first when
  # descending - so a page reading its own rows shows them where the server put them.
  defp compare_keys(nil, nil, _direction, _ranks), do: :eq

  defp compare_keys(nil, _right, :asc, _ranks), do: :gt

  defp compare_keys(_left, nil, :asc, _ranks), do: :lt

  defp compare_keys(nil, _right, :desc, _ranks), do: :lt

  defp compare_keys(_left, nil, :desc, _ranks), do: :gt

  defp compare_keys(left, right, direction, ranks) do
    result = compare(left, right, ranks)

    if direction == :desc do
      flip(result)
    else
      result
    end
  end

  # Values of one kind, compared the way that kind is ordered rather than the way its
  # representation happens to sort: two dates are two maps to a term comparison, which would
  # read their days before their years.
  defp compare_values(%Date{} = left, %Date{} = right), do: Date.compare(left, right)

  defp compare_values(%DateTime{} = left, %DateTime{} = right) do
    DateTime.compare(left, right)
  end

  defp compare_values(%Time{} = left, %Time{} = right), do: Time.compare(left, right)

  defp compare_values(left, right) when left < right, do: :lt

  defp compare_values(left, right) when left > right, do: :gt

  defp compare_values(_left, _right), do: :eq

  defp flip(:eq), do: :eq

  defp flip(:gt), do: :lt

  defp flip(:lt), do: :gt

  # Every key of the order is spent before two rows are called equal, and a normalized query's keys
  # always hold the id, so no two of its rows ever are.
  defp precedes?(_left_values, _right_values, [], _ranks), do: false

  defp precedes?(
         [left_value | left_rest],
         [right_value | right_rest],
         [{name, direction} | rest],
         ranks
       ) do
    case compare_keys(left_value, right_value, direction, Map.get(ranks, name)) do
      :eq -> precedes?(left_rest, right_rest, rest, ranks)
      :lt -> true
      :gt -> false
    end
  end
end
