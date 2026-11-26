defmodule Hologram.Migration.Value.Loader do
  @moduledoc false

  # Reads rows in the shape Hologram.Migration.Value.Evaluator takes, from a mapping at any point
  # in a migration's history, so it asks nothing of the app's compiled entity modules. It uses the
  # connection the caller is on, which inside a migration is the file's transaction.

  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Entity
  alias Hologram.Migration.Value.Evaluator

  @system_columns Enum.map(Entity.system_attributes(), fn {name, _type, _opts} ->
                    Atom.to_string(name)
                  end)

  @doc """
  Returns the rows of the given entity type with the given ids, in the order given and leaving out
  an id no row holds, each with the related data the given tree of reads names (see
  `Hologram.Migration.Value.Evaluator.reads/1`).

  Outside a transaction its reads come from one snapshot. Inside one, each read sees the database
  as the caller's transaction does, so they agree only under REPEATABLE READ or locks keeping
  writers off the tables read.
  """
  @spec load(%{(atom | {module, atom}) => map}, module, list(String.t()), %{
          module => %{atom => any}
        }) ::
          list(Evaluator.row())
  def load(reads, entity_type, ids, mapping) do
    # The rows come back keyed by the dashed spelling, which a compact id has to take to find its
    # row.
    ids = Enum.map(ids, &Codec.decode(Codec.encode(&1, :uuid), :uuid))

    # One snapshot where the caller isn't in a transaction already, since a load is several
    # statements that have to agree.
    {:ok, rows} =
      Connection.snapshot(fn ->
        load_rows(Map.fetch!(mapping, entity_type), "id", ids, reads, mapping)
      end)

    ids
    |> Enum.map(&Map.get(rows, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp attach(rows, _entry, reads, _mapping) when reads == %{}, do: rows

  defp attach(rows, entry, reads, mapping) do
    Enum.reduce(reads, rows, fn
      {{type, ref}, subtree}, acc ->
        attach_referencing(acc, type, ref, subtree, mapping)

      {name, subtree}, acc ->
        case join_table(entry, name) do
          nil -> attach_to_one(acc, entry, name, subtree, mapping)
          join_table -> attach_to_many(acc, join_table, name, subtree, mapping)
        end
    end)
  end

  defp attach_referencing(rows, type, ref, subtree, mapping) do
    entry = Map.fetch!(mapping, type)
    column = Enum.find(entry.columns, &(&1.source == {:relationship, ref}))

    reference = reference_key(ref)

    grouped =
      entry
      |> load_rows(column.name, Map.keys(rows), subtree, mapping)
      |> Map.values()
      |> Enum.group_by(&Map.get(&1, reference))

    Map.new(rows, fn {id, row} -> {id, Map.put(row, {type, ref}, Map.get(grouped, id, []))} end)
  end

  defp attach_to_many(rows, join_table, name, subtree, mapping) do
    statement = """
    SELECT "source_id", "target_id"
    FROM #{qualified(join_table.name)}
    WHERE "source_id" = ANY($1::uuid[])
    ORDER BY "source_id", "target_id"
    """

    {:ok, %{rows: edges}} = Connection.query(statement, [encode_ids(Map.keys(rows))])

    pairs =
      Enum.map(edges, fn [source_id, target_id] ->
        {Codec.decode(source_id, :uuid), Codec.decode(target_id, :uuid)}
      end)

    target_ids =
      pairs
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq()

    targets =
      load_rows(entry_for!(mapping, join_table.target_table), "id", target_ids, subtree, mapping)

    # Inside a caller's transaction each statement reads the database as it stands, so a target
    # deleted since the edges were read is simply no longer in the set.
    grouped =
      pairs
      |> Enum.filter(fn {_source_id, target_id} -> Map.has_key?(targets, target_id) end)
      |> Enum.group_by(&elem(&1, 0), &Map.fetch!(targets, elem(&1, 1)))

    Map.new(rows, fn {id, row} -> {id, Map.put(row, name, Map.get(grouped, id, []))} end)
  end

  defp attach_to_one(rows, entry, name, subtree, mapping) do
    column = Enum.find(entry.columns, &(&1.source == {:relationship, name}))
    reference = reference_key(name)

    target_ids =
      rows
      |> Map.values()
      |> Enum.map(&Map.get(&1, reference))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    targets =
      load_rows(entry_for!(mapping, column.references), "id", target_ids, subtree, mapping)

    Map.new(rows, fn {id, row} ->
      {id, Map.put(row, name, Map.get(targets, Map.get(row, reference)))}
    end)
  end

  defp decode(nil, _type), do: nil

  defp decode(value, type), do: Codec.decode(value, type)

  defp encode_ids(ids), do: Enum.map(ids, &Codec.encode(&1, :uuid))

  defp entry_for!(mapping, table) do
    {_entity_type, entry} = Enum.find(mapping, fn {_type, entry} -> entry.table == table end)

    entry
  end

  defp field_key(%{source: {:attribute, name}}), do: name

  defp field_key(%{source: {:relationship, name}}), do: reference_key(name)

  # The system columns a row shows are the ones every entity declares, whose atoms exist.
  defp field_key(%{name: name, source: :system}) when name in @system_columns do
    String.to_existing_atom(name)
  end

  defp field_key(_column), do: nil

  defp join_table(entry, name), do: Enum.find(entry.join_tables, &(&1.relationship == name))

  # The rows of the entry whose given uuid column holds one of the given ids, by their own id.
  defp load_rows(_entry, _column, [], _reads, _mapping), do: %{}

  defp load_rows(entry, column, ids, reads, mapping) do
    columns = Enum.filter(entry.columns, &(field_key(&1) != nil))
    selected = Enum.map_join(columns, ", ", &Mapper.quote_identifier(&1.name))

    statement = """
    SELECT #{selected}
    FROM #{qualified(entry.table)}
    WHERE #{Mapper.quote_identifier(column)} = ANY($1::uuid[])
    """

    {:ok, %{rows: rows}} = Connection.query(statement, [encode_ids(ids)])

    rows
    |> Map.new(fn values ->
      row = to_row(columns, values)

      {row.id, row}
    end)
    |> attach(entry, reads, mapping)
  end

  defp qualified(table) do
    "#{Mapper.quote_identifier(Mapper.data_schema())}.#{Mapper.quote_identifier(table)}"
  end

  # The name comes from the migration's own source, so it's bounded by the file.
  # sobelow_skip ["DOS.BinToAtom"]
  defp reference_key(name) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    :"#{name}_id"
  end

  defp to_row(columns, values) do
    columns
    |> Enum.zip(values)
    |> Map.new(fn {column, value} -> {field_key(column), decode(value, column.type)} end)
  end
end
