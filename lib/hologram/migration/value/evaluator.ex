defmodule Hologram.Migration.Value.Evaluator do
  @moduledoc false

  # Runs a resolved backfill on one row in Elixir, giving what the database gives for that row.
  #
  # A row is a map holding its attributes by name, `:id`, `:created_at`, `:updated_at`,
  # `:server_created_at`, `:server_updated_at` and each to-one's reference as `:<relationship>_id`,
  # in their native values: decoded, enums as atoms, uuids as lowercase canonical strings. For each
  # read `reads/1` names it also holds the related data: under a to-one's name the related row, in
  # the same shape and nil when the reference is nil, and under a stored to-many's name a list of
  # rows. Hologram.Migration.Value.Loader builds rows in this shape.

  alias Hologram.Migration.Value.Resolver
  alias Hologram.Query.Words

  @doc """
  Returns the value the given resolved term computes for the given row.
  """
  @spec evaluate(Resolver.resolved(), %{atom => any}) :: any
  def evaluate({:value, value, _type}, _row), do: value

  def evaluate({:name, path, _type}, row), do: read_path(row, path)

  def evaluate({:concat, operands}, row) do
    operands
    |> Enum.map(&evaluate(&1, row))
    |> Words.concat()
  end

  def evaluate({:at, {:split, text, {:value, separator, _type}}, {:value, position, _n}}, row) do
    text
    |> evaluate(row)
    |> Words.split(separator)
    |> Words.at(position)
  end

  def evaluate({:coalesce, values}, row) do
    values
    |> Enum.map(&evaluate(&1, row))
    |> Words.coalesce()
  end

  def evaluate({:count, {:relationship, path}}, row) do
    row
    |> read_set(path)
    |> Words.count()
  end

  def evaluate({:most_common, {:relationship, path}, attribute, _type, ranks}, row) do
    row
    |> read_set(path)
    |> Enum.map(&Map.get(&1, attribute))
    |> Words.most_common(rank_map(ranks))
  end

  @doc """
  Returns the related data the given resolved term reads beyond the row's own fields, as a tree: a
  map from each relationship to what's read through it.
  """
  @spec reads(Resolver.resolved()) :: %{atom => map}
  def reads({:value, _value, _type}), do: %{}

  def reads({:name, path, _type}) do
    path
    |> Enum.drop(-1)
    |> tree()
  end

  def reads({:concat, operands}), do: merge_reads(operands)

  def reads({:at, {:split, text, _separator}, _position}), do: reads(text)

  def reads({:coalesce, values}), do: merge_reads(values)

  def reads({:count, {:relationship, path}}), do: tree(path)

  def reads({:most_common, {:relationship, path}, _attribute, _type, _ranks}), do: tree(path)

  defp deep_merge(left, right) do
    Map.merge(left, right, fn _name, left_tree, right_tree ->
      deep_merge(left_tree, right_tree)
    end)
  end

  defp merge_reads(terms) do
    terms
    |> Enum.map(&reads/1)
    |> Enum.reduce(%{}, &deep_merge/2)
  end

  defp rank_map(nil), do: nil

  defp rank_map(values) do
    values
    |> Enum.with_index()
    |> Map.new()
  end

  defp read_path(nil, _path), do: nil

  defp read_path(row, [name]), do: Map.get(row, name)

  defp read_path(row, [hop | rest]) do
    row
    |> Map.get(hop)
    |> read_path(rest)
  end

  defp read_set(nil, _path), do: []

  defp read_set(row, [name]), do: Map.get(row, name, [])

  defp read_set(row, [hop | rest]) do
    row
    |> Map.get(hop)
    |> read_set(rest)
  end

  defp tree(path) do
    path
    |> Enum.reverse()
    |> Enum.reduce(%{}, fn name, subtree -> %{name => subtree} end)
  end
end
