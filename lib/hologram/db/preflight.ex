defmodule Hologram.DB.Preflight do
  @moduledoc false

  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.DDL
  alias Hologram.DB.Introspection

  @doc """
  Validates that the existing rows can follow the given op, against the database as it
  stands now, the way run!/3 does for a list of ops.

  A migration file checks each op right before applying it, so the check sees the names
  and the schema the file's earlier ops left - a rename included. A refusal still comes
  before the refused op's own DDL, and the file's transaction takes back the ops before
  it. The trade is that the check runs while those earlier ops hold their locks, after
  their work - which a file that applies pays anyway.

  A column counts as filled only when the op carries its fill - the renderer stamps a
  declared default where the op sits, as :backfill on an add and :fill on a tightening. A
  lookup in the mapping the file leaves would find the column under the name of whatever
  holds it at the end of the file: nothing, after a rename, or another column that took
  the name over, and the check would pass a fill the migrator never runs. Whether a
  tightening's fill makes rows repeat a unique key is asked when the fill runs (see
  check_fill!/1).

  The schema is read only for an op the checks can refuse, so a file of renames, plain
  indexes or safe casts costs no catalog reads.
  """
  @spec check!(%{atom => any}) :: :ok
  def check!(op) do
    if refusable?(op) do
      check_op!(op, Introspection.schema(), %{})
    end

    :ok
  end

  @doc """
  Validates that the given alter_column op's type change makes no rows repeat a key of a
  unique index standing over its column at this moment.

  Returns :ok, or raises naming the column, the key and how many keys would repeat. Two values
  can convert to one, as the texts '1' and '01' do to int8, and under a unique index the
  change itself would then fail. Asked right before the change applies, against the indexes
  standing then: the mapping a run converges to names them as it ends, and a migration file
  can rename or drop them on the way. An index the run builds later is not standing yet, and
  is asked about when it is built. The query converts the rows as the change does, so a row
  the change cannot take fails it as it would fail the change - the rows check of check!/1
  and run!/3 counts those rows first.

  An index introspection marks as not plain is hand-made, and is skipped: its key may be an
  expression or cover part of the table, which this count cannot follow. The drift and alien
  checks report it, but only on a run that gets past this change: until then the change
  itself fails on the index, in PostgreSQL's words.
  """
  @spec check_cast!(%{atom => any}) :: :ok
  def check_cast!(%{before: %{type: type}, after: %{type: type}}), do: :ok

  def check_cast!(op) do
    op.table
    |> standing_unique_indexes(op.column)
    |> Enum.each(fn index ->
      statement =
        DDL.cast_duplicate_check_statement(
          op.table,
          index.columns,
          op.column,
          op.after.type,
          index.nulls_distinct
        )

      raise_cast_duplicate_keys!(op, index.columns, count_result(statement))
    end)
  end

  @doc """
  Validates that filling the NULLs of the given table's column with the given encoded value
  makes no rows repeat a key of a unique index the mapping gives the table.

  Returns :ok, or raises naming the column, the key and how many keys would repeat. A column
  made required takes its default in the rows that hold NULL, and NULL never repeats a key
  while the default can - under an index that already stands the fill itself would fail, so
  this asks before it. Only the keys the fill would make repeat are counted: rows that repeat
  a key without it are the index build's to refuse.
  """
  @spec check_fill!(%{module => %{atom => any}}, String.t(), String.t(), any) :: :ok
  def check_fill!(mapping, table, column_name, encoded_value) do
    mapping
    |> unique_indexes(table)
    |> Enum.filter(&(column_name in &1.columns))
    |> check_filled_keys!(table, column_name, encoded_value)
  end

  @doc """
  Validates the same for a migration's tightening that carries its fill, against the unique
  indexes standing over its column at this moment.

  The mapping the file leaves names the indexes as the file ends, and a rename later in the
  file has not happened yet where the fill runs, so the catalog is read instead - as
  check_cast!/1 does, and skipping the hand-made indexes it skips. An invalid index that
  takes no writes is skipped too: the fill doesn't go through it, and whoever builds it
  later counts the keys then.
  """
  @spec check_fill!(%{atom => any}) :: :ok
  def check_fill!(op) do
    op.table
    |> standing_unique_indexes(op.column, not_ready_invalid_indexes())
    |> check_filled_keys!(op.table, op.column, op.fill)
  end

  @doc """
  Validates that no invalid unique index on the given table that the given change goes
  through meets rows repeating its key, except the ones the given function lets go.

  Returns the names of the indexes it let go, for the caller to drop before the change, or
  raises naming the table, the index's columns and how many keys repeat. The boot leaves
  such an index when its build before the pending files fails on those rows, which a running
  node can write while the index is missing, and so does a node writing them while a file's
  index builds after its commit. A valid unique index holds no repeated key, so only the
  invalid ones are counted, and the schema is read only when there are any.

  The function is asked about each index whose key repeats, with its name and whether the
  index covers a column the change converts or fills - a column whose values the change
  itself could make repeat a key. The migrator lets go an index that a later pending op
  removes, unless the pending files also give the table a unique index and change keys the
  index would have been asked about.

  A `{:rewrite, columns}` - a type change of those columns - rebuilds every index on its
  table, invalid ones included, and rebuilding a unique one fails on rows that repeat its key.
  The one it passes over is a dead index, which a concurrent drop that stopped partway
  leaves, unless the index covers a converted column: the type change then builds it again
  from its definition. An :update - a fill of every row - puts the rows it writes back into
  every index that takes writes, which an invalid one does when its build failed in its last
  phase, over a repeat written while it ran: putting back a row with the repeated key fails.
  One that takes no writes, as a build failing in its first phase leaves, is passed over. A
  `{:fill, column}` writes only the rows where the column is NULL, so only a repeated key one
  of those rows holds counts. In an index over the column that keeps nulls distinct those
  rows hold no key yet, and the one they take is check_fill!/1's to ask about.

  An index introspection marks as not plain is hand-made, and is skipped, as check_cast!/1
  skips it.
  """
  @spec check_invalid_unique_indexes!(
          String.t(),
          {:rewrite, [String.t()]} | :update | {:fill, String.t()},
          (String.t(), boolean -> boolean)
        ) :: [String.t()]
  def check_invalid_unique_indexes!(table, change, removable?) do
    invalid = invalid_indexes()

    if map_size(invalid) > 0 do
      Introspection.schema().tables[table].indexes
      |> Enum.sort_by(fn {name, _index} -> name end)
      |> Enum.filter(fn {name, index} ->
        Map.has_key?(invalid, name) and index.unique and not Map.has_key?(index, :non_plain) and
          goes_through?(change, invalid[name], index.columns)
      end)
      |> Enum.flat_map(&let_go_or_raise!(&1, table, change, removable?))
    else
      []
    end
  end

  @doc """
  Validates that the rows the given unique index op's table holds at this moment repeat no key
  of the index.

  Returns :ok, or raises naming the table, its columns and how many keys repeat. The check run!/3
  makes before any DDL sees the rows as they stood then, so a run that adds a column filled
  with its default asks again here, with every column of the index in place. The boot's index
  repair asks too, before it builds an index and after a build fails, since running nodes can
  write rows that repeat a key while the index is missing.
  """
  @spec check_unique_index!(%{atom => any}) :: :ok
  def check_unique_index!(op) do
    statement = DDL.duplicate_check_statement(op.table, op.columns, op.nulls_distinct)

    raise_duplicate_keys!(op, count_result(statement))
  end

  @doc """
  Returns the encoded fill value for the given table's column, or :none when the column
  declares no default.

  A required column arriving on a populated table takes its declared default: the value
  fills the existing rows before the column tightens, so the DDL never carries values.
  """
  @spec fill_value(%{module => %{atom => any}}, String.t(), String.t()) ::
          {:ok, any} | :none
  def fill_value(mapping, table, column_name) do
    entity_mapping = entity_mapping(mapping, table)

    column = entity_mapping && Enum.find(entity_mapping.columns, &(&1.name == column_name))

    case column do
      %{default: nil} -> :none
      %{default: default, type: type} -> {:ok, Codec.encode(default, type)}
      nil -> :none
    end
  end

  @doc """
  Validates that the existing rows can follow the given change ops, against the given
  introspected schema and mapping.

  Returns :ok, or raises naming the obstacle and the ways out - the transformations rows
  cannot follow fail before the DDL that would apply them runs, so PostgreSQL never
  arbitrates: an error surfacing from an apply is by definition a Hologram bug.

  A check against a table the ops create, or a unique index over a column they add, answers
  zero without a query: the table holds no rows yet, and the column is not there to ask
  about. A reconciliation that fills columns asks about its unique indexes again: before it
  fills the NULLs of a column that stands (see check_fill!/4), and right before it builds an
  index (see check_unique_index!/1). A migration asks before its fill (see check_fill!/1),
  and checks its tail's index builds with this function after the file's ops, the added
  columns filled.

  A type change asks once more right before it applies, about the unique indexes standing
  over its column then (see check_cast!/1), and before that about the invalid unique indexes
  on its table, which the change rebuilds (see check_invalid_unique_indexes!/3). A fill asks
  the same about the invalid unique indexes that still take writes.

  An enum rebuild's removed values exclude the ones an unscoped remap carries: those rows
  follow the value to its new label rather than losing it.
  """
  @spec run!(list(%{atom => any}), %{atom => any}, %{module => %{atom => any}}) :: :ok
  def run!(ops, actual, mapping) do
    Enum.each(ops, &check_op!(&1, actual, mapping))
  end

  defp check_op!(%{op: :add_column} = op, actual, mapping) do
    # An op carrying its own backfill needs no declared default - a migration states what
    # the rows that predate the column receive.
    filled? =
      Map.has_key?(op, :backfill) or
        match?({:ok, _value}, fill_value(mapping, op.table, op.column))

    checked? = not op.definition.null and not filled?

    count =
      if checked?,
        do: count_existing(actual, op.table, DDL.rows_check_statement(op.table)),
        else: 0

    if count > 0 do
      raise ~s(cannot add required column "#{op.column}" to table "#{op.table}" - ) <>
              "#{count} existing #{pluralize_rows(count)} would have no value - " <>
              "declare default: <value>, make the attribute optional: true, or clear the rows"
    end
  end

  defp check_op!(%{op: :alter_column} = op, actual, mapping) do
    check_type_change!(op, actual)
    check_null_tightening!(op, actual, mapping)
  end

  # An index over a column the run adds is not asked about here: the column is not there to
  # query. A unique attribute declares no default, so its column arrives NULL in every row, and
  # NULL is never a duplicate key on a declared unique index, which keeps nulls distinct - the
  # one index comparing nulls as values, the role grant store's, is born with its table. A key
  # declared with unique may name a column that arrives filled with its default, though - so
  # a run asks again right before it builds the index, with the added columns filled (see
  # check_unique_index!/1). A run filling the NULLs of a column that stands asks before that
  # fill (see check_fill!/4).
  defp check_op!(%{op: :create_index, unique: true} = op, actual, _mapping) do
    statement = DDL.duplicate_check_statement(op.table, op.columns, op.nulls_distinct)

    raise_duplicate_keys!(op, count_existing(actual, op.table, op.columns, statement))
  end

  # An enum type absent from the schema has no values to lose. A migration file checks
  # against the schema its earlier ops left, so a type an earlier chunk of the file created
  # is there with the values it was created with, and only its rows are counted. Schema
  # reconciliation checks a whole diff against one read, where a type the diff creates is
  # absent.
  defp check_op!(%{op: :rebuild_enum_type} = op, actual, _mapping) do
    existing_values = Map.get(actual.enum_types, op.enum_type, [])
    removed_values = (existing_values -- op.values) -- carried_values(op)

    if removed_values != [] do
      Enum.each(op.columns, fn {table, column} ->
        check_removed_enum_values!(actual, table, column, removed_values)
      end)
    end
  end

  defp check_op!(_op, _actual, _mapping), do: :ok

  # The ops a check_op!/3 clause above can refuse - kept next to those clauses so the two
  # cannot drift. An add carrying its backfill, a tightening carrying its fill, a plain
  # index and a safe cast never are; the keys a fill or a cast could make repeat are asked
  # about as it applies (check_fill!/1, check_cast!/1). A migration's in-transaction unique
  # index sits on a table the file creates, so its clause never counts a row there; it stays
  # for parity with check_op!/3.
  defp refusable?(%{op: :add_column} = op) do
    not op.definition.null and not Map.has_key?(op, :backfill)
  end

  defp refusable?(%{op: :alter_column} = op) do
    DDL.cast_class(op.before.type, op.after.type) != :safe or
      (op.before.null and not op.after.null and not Map.has_key?(op, :fill))
  end

  defp refusable?(%{op: :create_index, unique: true}), do: true

  defp refusable?(%{op: :rebuild_enum_type}), do: true

  defp refusable?(_op), do: false

  defp check_filled_keys!(indexes, table, column_name, encoded_value) do
    Enum.each(indexes, fn index ->
      statement =
        DDL.filled_duplicate_check_statement(
          table,
          index.columns,
          column_name,
          index.nulls_distinct
        )

      {:ok, %{rows: [[count]]}} = Connection.query(statement, [encoded_value])

      raise_filled_duplicate_keys!(table, column_name, index.columns, count)
    end)
  end

  defp check_cast_rows!(op, actual) do
    statement = DDL.cast_check_statement(op.table, op.column, op.before.type, op.after.type)
    count = count_existing(actual, op.table, statement)

    if count > 0 do
      raise ~s(#{count} #{pluralize_rows(count)} in "#{op.table}"."#{op.column}" ) <>
              "cannot convert from #{op.before.type} to #{op.after.type} - " <>
              "fix the data or remove the attribute and re-add it with the new type"
    end
  end

  # A value the rebuild carries to a new label is not a value it removes: the rows holding it
  # follow it through the remap, so counting them would refuse the very rename doing the
  # carrying. Only an UNSCOPED entry says that of every row - a scoped one carries the rows of
  # one entity type and leaves the rest, which is a removal for those.
  defp carried_values(op) do
    op
    |> Map.get(:remap, [])
    |> Enum.filter(&(&1.scope == nil))
    |> Enum.map(& &1.from)
  end

  defp check_null_tightening!(op, actual, mapping) do
    # A migration's tightening carries its fill, stamped by the renderer; schema
    # reconciliation's is looked up in the mapping.
    fillable? =
      op.before.type == op.after.type and
        (Map.has_key?(op, :fill) or
           match?({:ok, _value}, fill_value(mapping, op.table, op.column)))

    checked? = op.before.null and not op.after.null and not fillable?
    statement = DDL.null_check_statement(op.table, op.column)
    count = if checked?, do: count_existing(actual, op.table, statement), else: 0

    if count > 0 do
      raise ~s(cannot make column "#{op.column}" on table "#{op.table}" required - ) <>
              "found #{count} #{pluralize_rows(count)} with NULL - " <>
              "declare default: <value>, keep the attribute optional: true, or fix the data"
    end
  end

  defp check_removed_enum_values!(actual, table, column, removed_values) do
    statement = DDL.enum_values_check_statement(table, column, removed_values)
    count = count_existing(actual, table, statement)

    if count > 0 do
      values = Enum.map_join(removed_values, ", ", &"'#{&1}'")

      raise ~s(found #{count} #{pluralize_rows(count)} in "#{table}"."#{column}" ) <>
              "holding removed enum #{pluralize_values(removed_values)} #{values} - " <>
              "update the rows or re-add the #{pluralize_values(removed_values)}"
    end
  end

  defp check_type_change!(op, actual) do
    if op.before.type != op.after.type do
      case DDL.cast_class(op.before.type, op.after.type) do
        :safe ->
          :ok

        :data_dependent ->
          check_cast_rows!(op, actual)

        :unsupported ->
          raise ~s(changing column "#{op.column}" on table "#{op.table}" ) <>
                  "from #{op.before.type} to #{op.after.type} is not supported - " <>
                  "remove the attribute and re-add it with the new type"
      end
    end
  end

  # Every check here counts the rows that cannot follow a change, and a table the ops
  # create has none to count - absent from the schema this runs against, the query would
  # raise undefined_table instead of answering zero. Schema reconciliation reaches it: it
  # checks a whole diff against one read, a create_table and the index on it included. A
  # migration file checks each op against the schema its earlier ops left, where the table
  # already stands.
  defp count_existing(actual, table, statement) do
    if Map.has_key?(actual.tables, table), do: count_result(statement), else: 0
  end

  # The same for a column the run adds to a table that stands: the query would raise
  # undefined_column, and the column has no rows' values to count yet.
  defp count_existing(actual, table, columns, statement) do
    case Map.fetch(actual.tables, table) do
      {:ok, %{columns: existing_columns}} ->
        if Enum.all?(columns, &Map.has_key?(existing_columns, &1)),
          do: count_result(statement),
          else: 0

      :error ->
        0
    end
  end

  defp count_result(statement) do
    {:ok, %{rows: [[count]]}} = Connection.query(statement)

    count
  end

  # An add fills a column that arrives with it, which no index standing before it covers.
  defp covers?({:rewrite, columns}, index_columns), do: Enum.any?(index_columns, &(&1 in columns))

  defp covers?({:fill, column}, index_columns), do: column in index_columns

  defp covers?(:update, _index_columns), do: false

  defp entity_mapping(mapping, table) do
    mapping
    |> Map.values()
    |> Enum.find(&(&1.table == table))
  end

  defp goes_through?({:rewrite, columns}, %{live?: live?}, index_columns) do
    live? or Enum.any?(index_columns, &(&1 in columns))
  end

  defp goes_through?(_update_or_fill, %{ready?: ready?}, _index_columns), do: ready?

  # The invalid indexes of the data schema, by name, with whether they take writes and are
  # live.
  defp invalid_indexes do
    {:ok, %{rows: rows}} = Connection.query(DDL.invalid_indexes_statement())

    Map.new(rows, fn [index, ready?, live?] -> {index, %{ready?: ready?, live?: live?}} end)
  end

  # The index's name when its key repeats and the caller lets it go, nothing when no key
  # repeats.
  defp let_go_or_raise!({name, index}, table, change, removable?) do
    statement =
      DDL.duplicate_check_statement(
        table,
        index.columns,
        index.nulls_distinct,
        written_column(change)
      )

    count = count_result(statement)

    cond do
      count == 0 -> []
      removable?.(name, covers?(change, index.columns)) -> [name]
      true -> raise_invalid_duplicate_keys!(table, index.columns, change, count)
    end
  end

  defp not_ready_invalid_indexes do
    for {index, %{ready?: false}} <- invalid_indexes(), into: MapSet.new(), do: index
  end

  defp raise_cast_duplicate_keys!(_op, _columns, 0), do: :ok

  defp raise_cast_duplicate_keys!(op, columns, count) do
    key = Enum.map_join(columns, ", ", &~s("#{&1}"))

    raise ~s(cannot change column "#{op.column}" on table "#{op.table}" ) <>
            "from #{op.before.type} to #{op.after.type} - " <>
            "#{count} #{pluralize_keys(count)} over (#{key}) would repeat once converted - " <>
            "fix the data, or drop the unique declaration before changing the type"
  end

  defp raise_duplicate_keys!(_op, 0), do: :ok

  defp raise_duplicate_keys!(op, count) do
    columns = Enum.map_join(op.columns, ", ", &~s("#{&1}"))

    raise ~s{found #{count} duplicate #{pluralize_keys(count)} in "#{op.table}" } <>
            "over (#{columns}) - a unique index cannot be built while rows repeat a " <>
            "key - update the rows or drop the unique declaration"
  end

  defp raise_invalid_duplicate_keys!(table, columns, change, count) do
    key = Enum.map_join(columns, ", ", &~s("#{&1}"))

    reason =
      if match?({:rewrite, _columns}, change),
        do: "and a type change on the table rebuilds it",
        else: "but it already checks the rows this file writes"

    raise ~s{found #{count} duplicate #{pluralize_keys(count)} in "#{table}" over (#{key}) - } <>
            "the unique index over it is not built yet, #{reason} - update the rows"
  end

  defp raise_filled_duplicate_keys!(_table, _column, _columns, 0), do: :ok

  defp raise_filled_duplicate_keys!(table, column, columns, count) do
    key = Enum.map_join(columns, ", ", &~s("#{&1}"))

    raise ~s(cannot make column "#{column}" on table "#{table}" required - ) <>
            "filling its NULLs with the default would make #{count} " <>
            "#{pluralize_keys(count)} repeat over (#{key}) - " <>
            "fix the data, keep the attribute optional: true, or drop the unique declaration"
  end

  defp pluralize_keys(1), do: "key"

  defp pluralize_keys(_count), do: "keys"

  defp pluralize_rows(1), do: "row"

  defp pluralize_rows(_count), do: "rows"

  defp pluralize_values([_value]), do: "value"

  defp pluralize_values(_values), do: "values"

  defp standing_unique_indexes(table, column, skipped_names \\ MapSet.new()) do
    Introspection.schema().tables[table].indexes
    |> Enum.sort_by(fn {name, _index} -> name end)
    |> Enum.reject(fn {name, _index} -> MapSet.member?(skipped_names, name) end)
    |> Enum.map(fn {_name, index} -> index end)
    |> Enum.filter(&(&1.unique and not Map.has_key?(&1, :non_plain) and column in &1.columns))
  end

  # The column indexes a mapping derives are never unique, so the entity's own index entries
  # hold every unique index of its table.
  defp unique_indexes(mapping, table) do
    indexes =
      case entity_mapping(mapping, table) do
        nil -> %{}
        %{indexes: indexes} -> indexes
      end

    indexes
    |> Enum.sort_by(fn {name, _index} -> name end)
    |> Enum.map(fn {_name, index} -> index end)
    |> Enum.filter(& &1.unique)
  end

  defp written_column({:fill, column}), do: column

  defp written_column(_all_rows), do: nil
end
