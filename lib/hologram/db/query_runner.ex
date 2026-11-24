defmodule Hologram.DB.QueryRunner do
  @moduledoc false

  alias Hologram.Auth
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.DB.QueryCompiler
  alias Hologram.Entity.Derived
  alias Hologram.Entity.Metadata
  alias Hologram.Policy
  alias Hologram.Query
  alias Hologram.Query.Stage
  alias Hologram.Sync.FinalSeq

  @doc """
  Runs the given normalized query term against the database and returns its decoded
  result - a list of entity structs for set queries, an entity struct or nil for
  single-result queries, and an integer for counting queries.

  Entity structs hold the mapping's fields under their declared names (to-one
  references under their `<name>_id` fields). Each included relationship fills its
  embed field - a nested entity struct or nil for a to-one include, a list of entity
  structs for a to-many include - and relationships the query did not include keep
  their NotIncluded defaults. An included derived field holds its value, read by its
  declared type, or the rows its definition holds - a list, or one struct or nil - each
  embedding what the definition and the include ask for. One not included keeps its
  NotIncluded default.

  `server_created_seq` and `server_updated_seq` read nil where they are above the limit (see
  `Hologram.Sync.FinalSeq.current/0`), in what the query returns and in what it filters, orders and
  computes by. `raw: true` reads them as stored, as sync does.

  Raises Hologram.MisuseError when the term holds a placeholder (see
  `Hologram.Query.Stage.assert_no_placeholders!/1`).
  """
  @spec run(Query.t(), %{module => %{atom => any}}, keyword) ::
          list(struct) | struct | integer | nil
  def run(term, mapping, opts \\ []) do
    Stage.assert_no_placeholders!(term)

    compiled = QueryCompiler.compile(term, mapping)
    limit = limit(opts)
    values = Enum.map(compiled.params, &resolve_param(&1, nil, limit))

    case Connection.query(compiled.sql, values) do
      {:ok, result} -> decode_result(result, term, mapping, limit)
      {:error, error} -> raise error
    end
  end

  # A session's user id may be any string, integer or atom, and one that isn't an id Hologram
  # generates names no user entity, so the rules read it as an anonymous session - the way
  # Hologram.Auth.can?/3 and the recheck do.
  @doc false
  @spec run_policied(Query.t(), %{module => %{atom => any}}, any, keyword) ::
          list(struct) | struct | integer | nil
  def run_policied(term, mapping, session_user_id, opts \\ []) do
    limit = limit(opts)
    {compiled, values} = compile_policied(term, mapping, session_user_id, limit)

    case Connection.query(compiled.sql, values) do
      {:ok, result} -> decode_result(result, term, mapping, limit)
      {:error, error} -> raise error
    end
  end

  # One value worked out by Postgres over the rows a query takes and the given session's user may
  # read: the given aggregate expression, over the query's rows as `"$rows"` - for whoever needs
  # less than the rows, where decoding every column of every row costs several times as much.
  # `"$rows"` holds the sequence numbers as stored, since only the query's conditions and order
  # mask them.
  @doc false
  @spec run_policied_aggregate(Query.t(), %{module => %{atom => any}}, any, String.t(), keyword) ::
          any
  def run_policied_aggregate(term, mapping, session_user_id, aggregate_sql, opts \\ []) do
    {compiled, values} = compile_policied(term, mapping, session_user_id, limit(opts))
    sql = ~s|SELECT #{aggregate_sql} FROM (#{compiled.sql}) AS "$rows"|

    case Connection.query(sql, values) do
      {:ok, %{rows: [[value]]}} -> value
      {:error, error} -> raise error
    end
  end

  @doc """
  Decides which of the given users may read each of the rows of the given entity type with the
  given ids, in one statement (see `Hologram.DB.QueryCompiler.recheck/4`), and reads each readable
  row's current values - and, when the given flag asks for them, the server's verdicts on the
  operations of the type it sends one on, for the users who may read it (see
  `Hologram.Auth.verdicts/2`).

  Takes the row ids as canonical entity ids, and the users as ids, nil for an anonymous one. A user
  id in any other spelling names no user entity, so it reads as an anonymous one, the way
  `Hologram.Auth.can?/3` answers it.

  Returns a map from the id of every row one of them may read to the row, decoded as `run/2`
  decodes it with no includes, its readers and its verdicts. The readers are `:all` when a rule
  answering the same for every user admits it, and otherwise the set of the given users who may
  read it, nil among them when an anonymous user may. An id is left out when its row is gone or
  none of the given users may read it.

  The verdicts hold, each keyed by verdict key, the read verdict true in each:

    * `:users` - the answers of each signed-in reader the rules of some operation depending on the
      user admit, by canonical id.
    * `:others` - the answers of every other signed-in reader: what the rules answering an
      operation the same for every user answer, since the others admit none of them.
    * `:anonymous` - the answers of an anonymous reader, nil when no anonymous user was given.

  With no verdicts asked for, or a type the server sends none on, every answer set is empty.
  """
  @spec recheck(module, %{module => %{atom => any}}, Enumerable.t(), list(any), boolean) ::
          %{String.t() => {struct, :all | MapSet.t(), map}}
  def recheck(entity_type, mapping, ids, user_ids, verdicts? \\ false) do
    canonical_user_ids = Enum.map(user_ids, &Auth.canonical_id/1)
    anonymous? = nil in canonical_user_ids
    compiled = QueryCompiler.recheck(entity_type, mapping, anonymous?, verdicts?)
    verdict_keys = Map.get(compiled, :verdicts, %{operations: [], read: []})

    flag_count =
      if verdict_keys.operations == [], do: 3, else: 5 + length(verdict_keys.operations)

    signed_in_user_ids =
      canonical_user_ids
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    values =
      Enum.map(compiled.params, fn
        :ids ->
          Enum.map(ids, &Codec.encode(&1, :uuid))

        :users ->
          Enum.map(signed_in_user_ids, &Codec.encode(&1, :uuid))

        {:value, encoded_value} ->
          encoded_value

        # A recheck reads for sync, which takes the numbers as stored.
        :final_seq ->
          FinalSeq.all_final()

        # Every user is read off a row of its own, so a slot for the acting user means a path
        # the expression did not reach - answering it with anybody would be wrong for everybody else.
        :actor ->
          raise ArgumentError, "the recheck of #{inspect(entity_type)} binds an acting user"
      end)

    case Connection.query(compiled.sql, values) do
      {:ok, %{rows: rows}} ->
        term = Stage.normalize(entity_type)

        Map.new(rows, fn row ->
          {column_values, [everyone, anonymous, reader_ids | verdict_columns]} =
            Enum.split(row, -flag_count)

          entity = decode_row(column_values, term, mapping, FinalSeq.all_final())
          readers = readers(everyone, anonymous, reader_ids)

          {entity.id, {entity, readers, verdicts(verdict_keys, verdict_columns, anonymous?)}}
        end)

      {:error, error} ->
        raise error
    end
  end

  defp decode_embed(nil, _sub_term, _mapping, _limit), do: nil

  defp decode_embed(values, sub_term, mapping, limit) when is_list(values) do
    Enum.map(values, &decode_embedded_map(&1, sub_term, mapping, limit))
  end

  defp decode_embed(object, sub_term, mapping, limit) do
    decode_embedded_map(object, sub_term, mapping, limit)
  end

  defp decode_embedded_map(object, sub_term, mapping, limit) do
    target_mapping = Map.fetch!(mapping, sub_term.entity)

    base_fields =
      target_mapping.columns
      |> Enum.reject(&(&1.source == :revisions or Mapper.derived?(&1)))
      |> Map.new(fn column ->
        value =
          object
          |> Map.fetch!(column.name)
          |> decode_embedded_value(column.type)
          |> masked(column, limit)

        {field_name(column), value}
      end)

    nested_fields =
      Map.new(sub_term.include, fn {name, nested_sub_term} ->
        nested_value =
          object
          |> Map.fetch!(Atom.to_string(name))
          |> decode_included(
            {sub_term.entity, name, nested_sub_term},
            mapping,
            limit,
            &decode_embedded_value/2
          )

        {name, nested_value}
      end)

    revisions_column = Enum.find(target_mapping.columns, &(&1.source == :revisions))

    revisions =
      object
      |> Map.fetch!(revisions_column.name)
      |> decode_embedded_value(revisions_column.type)
      |> revisions_from_row(target_mapping.columns)

    struct!(
      sub_term.entity,
      base_fields
      |> Map.merge(nested_fields)
      |> Map.put(:__meta__, %Metadata{revisions: revisions})
    )
  end

  defp decode_embedded_value(nil, _type), do: nil

  # Read the way the codec reads a date it wrote, since Postgres spells a year past 9999 with all
  # its digits here too and Date.from_iso8601/1 reads no more than four.
  defp decode_embedded_value(value, :date) do
    {:ok, date} = Codec.decode_json(value, :date)
    date
  end

  # JSON writes a fraction without its trailing zeros, so an instant arriving this way carries
  # whatever precision its digits imply, where the same instant read from the column carries all
  # six. Two structs of one instant that compare unequal is a difference an application meets as
  # a bug - the same row read two ways answering differently - so what arrives here is
  # normalized the way the column path already normalizes it.
  defp decode_embedded_value(value, :datetime) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(value)

    Codec.encode(datetime, :datetime)
  end

  defp decode_embedded_value(value, :enum), do: Codec.decode_enum_label(value)

  # JSON writes a whole float as a whole number, so 7.0 arrives as 7 - read back as the float the
  # column holds.
  defp decode_embedded_value(value, :float) when is_integer(value), do: value * 1.0

  # Same story as :datetime one type over - JSON drops a fraction's trailing zeros, so a time
  # arriving this way is spelled shorter than the same time read from its own column, which is
  # always six digits. Promoted here so that one time of day is one struct however it was read.
  defp decode_embedded_value(value, :time) do
    value
    |> Time.from_iso8601!()
    |> Codec.encode(:time)
  end

  defp decode_embedded_value(value, _type), do: value

  # What an include holds: the related rows it embeds, a derived field's value read by its declared
  # type with the given decoder, or the rows a derived field holding rows embeds, each read with
  # what its definition and the include embed.
  defp decode_included(value, {entity_type, name, nil}, _mapping, _limit, decode_value) do
    {^name, type, _opts} = List.keyfind(entity_type.__derived__(), name, 0)

    decode_value.(value, type)
  end

  defp decode_included(value, {entity_type, name, sub_term}, mapping, limit, _decode_value) do
    rows_term = Derived.rows_term(entity_type, name, sub_term)

    decode_embed(value, rows_term, mapping, limit)
  end

  defp decode_result(%{rows: [[count]]}, %{cardinality: :count}, _mapping, _limit), do: count

  defp decode_result(%{rows: rows}, %{cardinality: :one} = term, mapping, limit) do
    case rows do
      [] -> nil
      [row] -> decode_row(row, term, mapping, limit)
    end
  end

  defp decode_result(%{rows: rows}, term, mapping, limit) do
    Enum.map(rows, &decode_row(&1, term, mapping, limit))
  end

  defp decode_row(row, term, mapping, limit) do
    entity_mapping = Map.fetch!(mapping, term.entity)
    selected_columns = Enum.reject(entity_mapping.columns, &Mapper.derived?/1)
    {column_values, include_values} = Enum.split(row, length(selected_columns))

    column_pairs = Enum.zip(selected_columns, column_values)

    # Exactly one revisions column per table, by construction - it is framework state rather than
    # a value the entity declares, so it lands in the metadata and never as a field.
    {[{revisions_column, revisions_value}], value_pairs} =
      Enum.split_with(column_pairs, fn {column, _value} -> column.source == :revisions end)

    base_fields =
      Map.new(value_pairs, fn {column, value} ->
        decoded = Codec.decode(value, column.type)
        {field_name(column), masked(decoded, column, limit)}
      end)

    include_fields =
      term.include
      |> Enum.sort_by(fn {name, _sub_term} -> name end)
      |> Enum.zip(include_values)
      |> Map.new(fn {{name, sub_term}, value} ->
        {name,
         decode_included(value, {term.entity, name, sub_term}, mapping, limit, &Codec.decode/2)}
      end)

    revisions =
      revisions_value
      |> Codec.decode(revisions_column.type)
      |> revisions_from_row(entity_mapping.columns)

    struct!(
      term.entity,
      base_fields
      |> Map.merge(include_fields)
      |> Map.put(:__meta__, %Metadata{revisions: revisions})
    )
  end

  defp field_name(%{source: :system, name: name}), do: String.to_existing_atom(name)

  defp field_name(%{source: {:attribute, name}}), do: name

  defp field_name(%{source: {:relationship, name}}), do: String.to_existing_atom("#{name}_id")

  # The limit is read once per statement, before it is sent: in read committed every save at or
  # below it has ended by then, so the statement's snapshot holds every row it makes final. Inside
  # `Hologram.DB.Connection.snapshot/1` the snapshot can be older than the limit - only sync reads
  # there, and sync reads raw.
  defp limit(opts) do
    if Keyword.get(opts, :raw, false), do: FinalSeq.all_final(), else: FinalSeq.current()
  end

  # A number above the limit is not final yet, so the row holds it as nil, the way the browser holds
  # it until it is.
  defp masked(value, column, limit) do
    if is_integer(value) and value > limit and Mapper.sequence?(column), do: nil, else: value
  end

  defp readers(true, _anonymous, _reader_ids), do: :all

  defp readers(false, anonymous, reader_ids) do
    readers = MapSet.new(reader_ids, &Codec.decode(&1, :uuid))

    if anonymous, do: MapSet.put(readers, nil), else: readers
  end

  defp compile_policied(term, mapping, session_user_id, limit) do
    Stage.assert_no_placeholders!(term)

    actor_user_id = Auth.canonical_id(session_user_id)

    policy = %{
      anonymous?: is_nil(actor_user_id),
      rules: read_rules(term.entity)
    }

    compiled = QueryCompiler.compile(term, mapping, policy)
    values = Enum.map(compiled.params, &resolve_param(&1, actor_user_id, limit))

    {compiled, values}
  end

  defp read_rules(entity_type) do
    entity_type
    |> Policy.build()
    |> Map.get(:read, [])
  end

  # The actor slot never appears in an anonymous statement - actor-referencing rules are
  # elided at composition, so there is no nil to bind.
  defp resolve_param(:actor, actor_user_id, _limit), do: Codec.encode(actor_user_id, :uuid)

  defp resolve_param(:final_seq, _actor_user_id, limit), do: limit

  defp resolve_param({:value, encoded_value}, _actor_user_id, _limit), do: encoded_value

  # The same reading EntityOperations.revisions_from_row/2 does for a by-id read, beside the
  # field_name/1 clauses this module already keeps its own copy of.
  defp revisions_from_row(revisions, columns) do
    revisions
    |> Enum.flat_map(fn {name, revision} ->
      case Enum.find(columns, &(&1.name == name)) do
        nil -> []
        column -> [{field_name(column), revision}]
      end
    end)
    |> Map.new()
  end

  # Every reader's verdicts start from the read verdict, true for every one of them, and from the
  # answers of the rules answering an operation the same for everyone. A reader is among an
  # operation's users when its other rules admit them, and a reader among no operation's users
  # answers each one as everyone does.
  defp verdicts(%{operations: [], read: read_keys}, [], anonymous?) do
    read_answers = Map.new(read_keys, &{&1, true})

    %{anonymous: if(anonymous?, do: read_answers), others: read_answers, users: %{}}
  end

  defp verdicts(verdict_keys, verdict_columns, anonymous?) do
    [everyone_answers, anonymous_answers | operation_user_ids] = verdict_columns

    read_answers = Map.new(verdict_keys.read, &{&1, true})

    others =
      verdict_keys.operations
      |> Enum.zip(everyone_answers)
      |> Map.new()
      |> Map.merge(read_answers)

    anonymous =
      if anonymous? do
        [verdict_keys.operations, everyone_answers, anonymous_answers]
        |> Enum.zip_with(fn [key, everyone?, anonymous?] -> {key, everyone? or anonymous?} end)
        |> Map.new()
        |> Map.merge(read_answers)
      end

    users =
      verdict_keys.operations
      |> Enum.zip(operation_user_ids)
      |> Enum.reduce(%{}, fn {key, user_ids}, acc ->
        Enum.reduce(user_ids, acc, fn user_id, user_acc ->
          Map.update(
            user_acc,
            Codec.decode(user_id, :uuid),
            %{key => true},
            &Map.put(&1, key, true)
          )
        end)
      end)
      |> Map.new(fn {user_id, admitted} -> {user_id, Map.merge(others, admitted)} end)

    %{anonymous: anonymous, others: others, users: users}
  end
end
