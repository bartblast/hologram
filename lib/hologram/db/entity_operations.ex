defmodule Hologram.DB.EntityOperations do
  @moduledoc false

  # The entity row and edge operations of the database gateway. The public surface lives
  # on Hologram.DB - these functions back its delegates, which also carry the docs.

  # SQL statements in this module interpolate ONLY framework-derived identifiers (always
  # through Mapper.quote_identifier/1) and $n placeholders - every value travels as a bound
  # param. The sobelow_skip markers on the emitting functions record that invariant.

  alias Hologram.Auth.Context
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Clock
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.DB.Outbox
  alias Hologram.DB.SortKey
  alias Hologram.Entity
  alias Hologram.Entity.Metadata
  alias Hologram.Entity.Validator

  @data_schema "hologram_data"

  @doc false
  @spec add_relationship(module, String.t(), atom, String.t()) :: :ok
  # sobelow_skip ["SQL.Query"]
  def add_relationship(entity_type, id, relationship_name, target_id) do
    join_table = fetch_join_table!(entity_type, relationship_name)

    statement =
      ~s|INSERT INTO #{qualified_table(join_table.name)} ("source_id", "target_id") VALUES ($1, $2) ON CONFLICT DO NOTHING|

    encoded_id = Codec.encode(id, :uuid)
    encoded_target_id = Codec.encode(target_id, :uuid)

    effect = %{
      op: :add_relationship,
      entity_type: entity_type,
      entity_id: id,
      relationship: relationship_name,
      target_id: target_id
    }

    {:ok, :ok} =
      Connection.transaction(fn ->
        run_edge_change!(statement, [encoded_id, encoded_target_id], effect)
      end)

    :ok
  end

  @doc false
  @spec create(struct) :: {:ok, struct} | {:error, %{atom => list(atom | {atom, any})}}
  def create(entity) do
    entity_type = entity.__struct__

    # Values are judged first - no write is attempted for an entity the declarations already
    # refuse.
    result =
      case Entity.validate(entity) do
        :ok ->
          # The transaction's own shape is the contract: its value is the stamped entity, and
          # whatever refused the write rolls back as its reason.
          Connection.transaction(fn ->
            {stamped_entity, _result} = insert(entity, "")

            Outbox.append([put_effect(stamped_entity)])

            # The grants ride in the create's own transaction rather than opening one each -
            # a row never exists without its creator's roles, and a nested transaction per
            # grant would be a savepoint per grant once transactions nest.
            entity
            |> creator_grants()
            |> Enum.each(&insert_if_absent/1)

            stamped_entity
          end)

        {:error, violations} ->
          {:error, violations}
      end

    # Whatever refused it, the answer is completed the same way - one merge point, so a caller
    # cannot tell from the map's shape which layer got there first.
    case result do
      {:ok, stamped_entity} ->
        {:ok, stamped_entity}

      {:error, refusal} ->
        violations = write_violations!(entity_type, refusal)
        values = Map.from_struct(entity)

        {:error, advisory_violations(entity_type, values, entity.id, violations)}
    end
  end

  @doc false
  @spec create_if_absent(struct) :: :ok
  def create_if_absent(entity) do
    # The framework writes its own grants through here, so a database refusal is a broken
    # invariant rather than something a caller can answer - it raises where create/1 explains.
    case Connection.transaction(fn -> insert_if_absent(entity) end) do
      {:ok, :ok} -> :ok
      {:error, %Postgrex.Error{} = error} -> raise error
    end
  end

  @doc false
  @spec delete(module, String.t()) :: :ok | {:error, %{referenced_by: module, relationship: atom}}
  def delete(entity_type, id) do
    %{table: table, join_tables: join_tables} = Map.fetch!(DB.mapping(), entity_type)

    encoded_id = Codec.encode(id, :uuid)

    transaction_result =
      Connection.transaction(fn ->
        delete_outgoing_edges(join_tables, encoded_id)

        # The edges the delete took with it are not recorded one by one: a row that is gone
        # takes whatever hung off it, and a reader learning the entity is gone knows that.
        if delete_entity_row(table, encoded_id) == 1 do
          Outbox.append([%{op: :del_entity, entity_type: entity_type, entity_id: id}])
        end

        :ok
      end)

    case transaction_result do
      {:ok, :ok} -> :ok
      {:error, _reason} = error -> error
    end
  end

  @doc false
  @spec delete_relationship(module, String.t(), atom, String.t()) :: :ok
  # sobelow_skip ["SQL.Query"]
  def delete_relationship(entity_type, id, relationship_name, target_id) do
    join_table = fetch_join_table!(entity_type, relationship_name)

    statement =
      ~s|DELETE FROM #{qualified_table(join_table.name)} WHERE "source_id" = $1 AND "target_id" = $2|

    encoded_id = Codec.encode(id, :uuid)
    encoded_target_id = Codec.encode(target_id, :uuid)

    effect = %{
      op: :del_relationship,
      entity_type: entity_type,
      entity_id: id,
      relationship: relationship_name,
      target_id: target_id
    }

    {:ok, :ok} =
      Connection.transaction(fn ->
        run_edge_change!(statement, [encoded_id, encoded_target_id], effect)
      end)

    :ok
  end

  # With lock: true the row is read FOR UPDATE, so it stays as read until the enclosing
  # transaction ends - what a write evaluated against the row as it stands needs, since nothing
  # can change the row between the evaluation and the write.
  @doc false
  @spec get(module, String.t(), keyword) :: struct | nil
  # sobelow_skip ["SQL.Query"]
  def get(entity_type, id, opts \\ []) do
    validate_id!(id)

    %{table: table, columns: columns} = Map.fetch!(DB.mapping(), entity_type)

    persisted_columns = Enum.reject(columns, &match?({:sort_key, _name}, &1.source))

    column_list = Enum.map_join(persisted_columns, ", ", &Mapper.quote_identifier(&1.name))
    lock_clause = if opts[:lock] == true, do: " FOR UPDATE", else: ""

    statement =
      ~s|SELECT #{column_list} FROM #{qualified_table(table)} WHERE "id" = $1#{lock_clause}|

    encoded_id = Codec.encode(id, :uuid)

    case Connection.query(statement, [encoded_id]) do
      {:ok, %Postgrex.Result{rows: []}} ->
        nil

      {:ok, %Postgrex.Result{rows: [row]}} ->
        # Exactly one revisions column per table, by construction - it is framework state rather
        # than a value the entity declares, so it lands in the metadata and never as a field.
        {[{revisions_column, revisions_value}], field_pairs} =
          persisted_columns
          |> Enum.zip(row)
          |> Enum.split_with(fn {column, _value} -> column.source == :revisions end)

        fields =
          Enum.map(field_pairs, fn {column, value} ->
            {field_name(column), Codec.decode(value, column.type)}
          end)

        revisions =
          revisions_value
          |> Codec.decode(revisions_column.type)
          |> revisions_from_row(columns)

        struct!(entity_type, [{:__meta__, %Metadata{revisions: revisions}} | fields])

      {:error, error} ->
        raise error
    end
  end

  @doc false
  @spec update(module, String.t(), map | keyword) ::
          :ok | {:error, %{atom => list(atom | {atom, any})}}
  # sobelow_skip ["SQL.Query"]
  def update(entity_type, id, changes) do
    %{table: table, columns: columns} = Map.fetch!(DB.mapping(), entity_type)

    columns_by_field =
      columns
      |> Enum.reject(
        &(&1.source in [:revisions, :system] or match?({:sort_key, _name}, &1.source))
      )
      |> Map.new(&{field_name(&1), &1})

    changes_map = Map.new(changes)
    sorted_changes = Enum.sort(changes_map)

    validate_changes!(entity_type, sorted_changes, columns_by_field)

    # Values are judged before the statement is built - nothing is written for changes the
    # declarations already refuse.
    result =
      case Entity.validate(entity_type, changes_map) do
        :ok ->
          change_entries =
            Enum.map(sorted_changes, fn {name, value} ->
              column = columns_by_field[name]

              {column, Codec.encode(value, column.type)}
            end)

          set_entries = change_entries ++ companion_entries(columns, sorted_changes)

          set_list =
            set_entries
            |> Enum.with_index(1)
            |> Enum.map_join(", ", fn {{column, _value}, index} ->
              "#{Mapper.quote_identifier(column.name)} = $#{index}"
            end)

          stamp_placeholder = length(set_entries) + 1
          updated_at_placeholder = length(set_entries) + 2
          id_placeholder = length(set_entries) + 3

          # One stamp for the whole statement, so every column it sets reads as set together.
          set_columns =
            set_entries
            |> Enum.map(fn {column, _value} -> column end)
            |> Enum.filter(&settable?/1)

          revisions_assignment = revisions_assignment(set_columns, stamp_placeholder)

          statement =
            ~s|UPDATE #{qualified_table(table)} SET #{set_list}, #{revisions_assignment}, "updated_at" = $#{updated_at_placeholder} WHERE "id" = $#{id_placeholder} RETURNING "$revisions"|

          changed_values = Enum.map(set_entries, fn {_column, value} -> value end)

          stamp = Clock.stamp()
          updated_at = DateTime.utc_now(:microsecond)
          encoded_updated_at = Codec.encode(updated_at, :datetime)
          encoded_id = Codec.encode(id, :uuid)

          params = changed_values ++ [stamp, encoded_updated_at, encoded_id]

          # The stamp travels with the changes: every update moves updated_at, and a client holding
          # the row holds that too. The sort-key companions do not - they are derived from the values
          # beside them, and a reader recomputes them rather than being told.
          data = Map.put(changes_map, :updated_at, updated_at)

          # The transaction's reason is whatever refused the write, the way create/1's is - a
          # refusal rolls the update back rather than raising.
          Connection.transaction(fn ->
            run_update!(statement, params, entity_type, id, data, set_columns)
          end)

        {:error, violations} ->
          {:error, violations}
      end

    # Whatever refused it, the answer is completed the same way - one merge point, so a caller
    # cannot tell from the map's shape which layer got there first.
    case result do
      {:ok, _appended} ->
        :ok

      {:error, refusal} ->
        violations = write_violations!(entity_type, refusal)

        {:error, advisory_violations(entity_type, changes_map, id, violations)}
    end
  end

  @doc false
  @spec validate_id!(any) :: :ok
  def validate_id!(id) do
    if not Validator.attribute_value_valid?(id, :uuid) do
      raise ArgumentError,
            "invalid id #{inspect(id)} - entity ids are canonical lowercase 8-4-4-4-12 UUID strings"
    end

    :ok
  end

  # A unique attribute is worth asking about only when the value could be compared at all: a
  # field carrying its own violation is not comparable, and nil never conflicts.
  defp advisory_candidate?({name, _type, opts}, values, violations) do
    Keyword.get(opts, :unique) == true and not Map.has_key?(violations, name) and
      not is_nil(values[name])
  end

  # A to-one reference is worth asking about only when it names something to look for: nil is a
  # cleared reference rather than a missing one, and a field carrying its own violation holds a
  # value no id column can be compared against - binding it would fail the query rather than
  # answer it. To-many relationships have no column here at all; their edges carry their own.
  defp advisory_reference_candidates(entity_type, values, violations) do
    entity_type.__relationships__()
    |> Enum.reject(fn {_name, target, _opts} -> is_list(target) end)
    |> Enum.map(fn {name, target, _opts} -> {String.to_existing_atom("#{name}_id"), target} end)
    |> Enum.filter(fn {field, _target} ->
      not Map.has_key?(violations, field) and not is_nil(values[field])
    end)
  end

  # Completes an answer that stopped early. The database names the first constraint it refused
  # and abandons the statement, so every unique attribute it never reached is asked about here,
  # as is every one of them when the values failed and no write was attempted at all. References
  # are asked about the same way and for the same reason: a foreign key is enforced by a trigger
  # after the row goes in, and the first one that fails abandons the rest. The candidate filters
  # leave a field that already carries a violation alone, so an authoritative answer is never
  # replaced by an advisory one - and references read the attributes' result rather than the
  # original map, so one pass cannot overwrite the other. Advisory by nature: what is taken now
  # may be free by the resubmit, and a target alive now may be gone - the resubmit is answered
  # by the write.
  defp advisory_violations(entity_type, values, id, violations) do
    %{table: table, columns: columns} = Map.fetch!(DB.mapping(), entity_type)

    attribute_violations =
      entity_type.__attributes__()
      |> Enum.filter(&advisory_candidate?(&1, values, violations))
      |> Enum.reduce(violations, fn {name, type, _opts}, acc ->
        column = Enum.find(columns, &(&1.source == {:attribute, name}))

        if unique_value_taken?(table, column.name, values[name], type, id) do
          Map.put(acc, name, [:unique])
        else
          acc
        end
      end)

    entity_type
    |> advisory_reference_candidates(values, attribute_violations)
    |> Enum.reduce(attribute_violations, fn {field, target}, acc ->
      if reference_target_exists?(target, values[field]) do
        acc
      else
        Map.put(acc, field, [:not_found])
      end
    end)
  end

  # The one place a column name is spliced into SQL as a LITERAL rather than as a quoted
  # identifier. Every name here comes from the mapping and never from a caller - the guard is
  # there because a name is still data, and a literal is the position where that would matter.
  defp column_literal(name) do
    if not String.match?(name, ~r/^[a-z0-9_]+$/) do
      raise ArgumentError, "cannot record a revision for column #{inspect(name)}"
    end

    "'#{name}'"
  end

  defp companion_entries(columns, sorted_changes) do
    changes_map = Map.new(sorted_changes)

    columns
    |> Enum.filter(fn column ->
      match?({:sort_key, _name}, column.source) and
        Map.has_key?(changes_map, elem(column.source, 1))
    end)
    |> Enum.map(fn %{source: {:sort_key, attribute_name}} = column ->
      encoded_key =
        changes_map
        |> Map.fetch!(attribute_name)
        |> compute_sort_key()
        |> Codec.encode(column.type)

      {column, encoded_key}
    end)
  end

  defp compute_sort_key(nil), do: nil

  defp compute_sort_key(value), do: SortKey.compute(value)

  # Returns how many rows the delete removed - deleting an id nothing holds removes none, and
  # is not something that happened to tell anyone about. A foreign key that refuses it is named
  # back to the relationship that derives it, so the caller learns who still needs the row - a
  # constraint the mapping does not know is not ours and raises.
  # sobelow_skip ["SQL.Query"]
  defp delete_entity_row(table, encoded_id) do
    statement = ~s|DELETE FROM #{qualified_table(table)} WHERE "id" = $1|

    case Connection.query(statement, [encoded_id]) do
      {:ok, %Postgrex.Result{num_rows: num_rows}} ->
        num_rows

      {:error,
       %Postgrex.Error{postgres: %{code: :foreign_key_violation, constraint: constraint}} =
           error} ->
        case Mapper.referencing_relationship(DB.mapping(), constraint) do
          {entity_type, relationship} ->
            Connection.rollback(%{referenced_by: entity_type, relationship: relationship})

          nil ->
            raise error
        end

      {:error, error} ->
        raise error
    end
  end

  # sobelow_skip ["SQL.Query"]
  defp delete_outgoing_edges(join_tables, encoded_id) do
    Enum.each(join_tables, fn join_table ->
      statement = ~s|DELETE FROM #{qualified_table(join_table.name)} WHERE "source_id" = $1|

      case Connection.query(statement, [encoded_id]) do
        {:ok, _result} -> :ok
        {:error, error} -> raise error
      end
    end)
  end

  # The creating user takes the entity type's creator roles as the row is inserted, in the
  # same transaction - so a resource never exists without whoever made it holding its roles.
  # Creating without an acting user grants nothing, which is what the trusted tier wants.
  defp creator_grants(entity) do
    entity_type = entity.__struct__

    case Context.actor_user_id() do
      nil ->
        []

      actor_user_id ->
        entity_type.__roles__()
        |> Enum.filter(fn {_name, opts} -> Keyword.get(opts, :creator) == true end)
        |> Enum.map(&creator_grant(&1, entity, entity_type, actor_user_id))
    end
  end

  defp creator_grant({role_name, _opts}, entity, entity_type, actor_user_id) do
    %RoleGrant{
      id: Entity.generate_id(),
      granted_by_id: actor_user_id,
      resource_id: entity.id,
      resource_type: RoleGrant.resource_type(entity_type),
      role: role_name,
      user_id: actor_user_id
    }
  end

  defp encoded_column_value(entity, %{source: {:sort_key, attribute_name}} = column) do
    entity
    |> Map.fetch!(attribute_name)
    |> compute_sort_key()
    |> Codec.encode(column.type)
  end

  defp encoded_column_value(entity, column) do
    entity
    |> Map.fetch!(field_name(column))
    |> Codec.encode(column.type)
  end

  defp fetch_join_table!(entity_type, relationship_name) do
    %{join_tables: join_tables} = Map.fetch!(DB.mapping(), entity_type)

    case Enum.find(join_tables, &(&1.relationship == relationship_name)) do
      nil ->
        raise ArgumentError,
              "invalid relationship for #{inspect(entity_type)} - #{inspect(relationship_name)} is not a declared to-many relationship"

      join_table ->
        join_table
    end
  end

  defp field_name(%{source: :system, name: name}), do: String.to_existing_atom(name)

  defp field_name(%{source: {:attribute, name}}), do: name

  defp field_name(%{source: {:relationship, name}}), do: String.to_existing_atom("#{name}_id")

  # sobelow_skip ["SQL.Query"]
  defp insert(entity, conflict_clause) do
    entity_type = entity.__struct__
    %{table: table, columns: columns} = Map.fetch!(DB.mapping(), entity_type)

    now = DateTime.utc_now(:microsecond)

    # One stamp for the whole row: every column it sets was set by this write, at this moment.
    stamp = Clock.stamp()
    settable_columns = Enum.filter(columns, &settable?/1)
    revisions = Map.new(settable_columns, &{field_name(&1), stamp})

    stamped_entity = %{
      entity
      | created_at: now,
        updated_at: now,
        __meta__: %{entity.__meta__ | revisions: revisions}
    }

    encoded_values =
      Enum.map(columns, fn
        %{source: :revisions} -> Map.new(settable_columns, &{&1.name, stamp})
        column -> encoded_column_value(stamped_entity, column)
      end)

    column_list = Enum.map_join(columns, ", ", &Mapper.quote_identifier(&1.name))
    placeholder_list = Enum.map_join(1..length(columns), ", ", &"$#{&1}")

    statement =
      "INSERT INTO #{qualified_table(table)} (#{column_list}) " <>
        "VALUES (#{placeholder_list})#{conflict_clause}"

    case Connection.query(statement, encoded_values) do
      {:ok, result} ->
        {stamped_entity, result}

      # The writer explains nothing: it rolls back with what refused it, and the verb that was
      # asked to write turns that into an answer or re-raises it.
      {:error, error} ->
        Connection.rollback(error)
    end
  end

  defp insert_if_absent(entity) do
    # The framework writes its own grants through this path, so an invalid one is a broken
    # invariant rather than something a caller can answer - it raises where create/1 returns.
    validate_entity!(entity.__struct__, entity)

    {stamped_entity, result} = insert(entity, " ON CONFLICT DO NOTHING")

    # A row that was already there is not a change, and the conflicting insert wrote
    # nothing - an effect recorded for it would be a change clients never saw happen.
    if result.num_rows == 1 do
      Outbox.append([put_effect(stamped_entity)])
    end

    :ok
  end

  # What the entity is, as the effect log records it: every column the row carries except the
  # sort-key companions, which are derived from the values beside them rather than written.
  defp put_effect(entity) do
    entity_type = entity.__struct__
    %{columns: columns} = Map.fetch!(DB.mapping(), entity_type)

    data =
      columns
      |> Enum.reject(&(&1.source == :revisions or match?({:sort_key, _name}, &1.source)))
      |> Map.new(fn column ->
        name = field_name(column)

        {name, Map.fetch!(entity, name)}
      end)

    %{
      op: :put_entity,
      entity_type: entity_type,
      entity_id: entity.id,
      data: data,
      revisions: entity.__meta__.revisions
    }
  end

  # An edge the database already had, or already lacked, is not a change: the statement wrote
  # nothing, and an effect for it would name a moment that never happened.
  defp run_edge_change!(statement, params, effect) do
    case Connection.query(statement, params) do
      {:ok, %Postgrex.Result{num_rows: 1}} ->
        Outbox.append([effect])

      {:ok, %Postgrex.Result{}} ->
        :ok

      {:error, error} ->
        raise error
    end
  end

  defp run_update!(statement, params, entity_type, id, data, set_columns) do
    case Connection.query(statement, params) do
      # The stored map comes back rather than the stamp that was sent: a column already past the
      # stamp keeps its own revision, so what the row now holds is the only true answer.
      {:ok, %Postgrex.Result{num_rows: 1, rows: [[stored_revisions]]}} ->
        Outbox.append([
          %{
            op: :patch_entity,
            entity_type: entity_type,
            entity_id: id,
            data: data,
            revisions: revisions_from_row(stored_revisions, set_columns)
          }
        ])

      {:ok, %Postgrex.Result{num_rows: 0}} ->
        raise ArgumentError,
              "cannot update #{inspect(entity_type)} - no entity with id #{inspect(id)}"

      # The writer explains nothing, the way insert/2 does not - update/3's merge point turns
      # what refused the write into an answer or re-raises it.
      {:error, error} ->
        Connection.rollback(error)
    end
  end

  defp qualified_table(table) do
    "#{Mapper.quote_identifier(@data_schema)}.#{Mapper.quote_identifier(table)}"
  end

  # Whether the row a reference names is there, asked of the TARGET type's own table - the one
  # question the mapping cannot answer from a declaration.
  # sobelow_skip ["SQL.Query"]
  defp reference_target_exists?(target, id) do
    %{table: table} = Map.fetch!(DB.mapping(), target)

    statement = ~s|SELECT EXISTS (SELECT 1 FROM #{qualified_table(table)} WHERE "id" = $1)|

    case Connection.query(statement, [Codec.encode(id, :uuid)]) do
      {:ok, %Postgrex.Result{rows: [[exists?]]}} -> exists?
      {:error, error} -> raise error
    end
  end

  # A to-one reference column carries the foreign key constraint that names it back, so a target
  # row that is gone is answered the way a value violation is - by field, in Entity.validate/1's
  # shape. Existence is state rather than a value, which is why the validator never reports it.
  defp reference_violations(entity_type, %Postgrex.Error{
         postgres: %{code: :foreign_key_violation, constraint: constraint}
       }) do
    %{columns: columns} = Map.fetch!(DB.mapping(), entity_type)

    case Enum.find(columns, &(&1.fk_constraint == constraint)) do
      %{source: {:relationship, name}} -> %{String.to_existing_atom("#{name}_id") => [:not_found]}
      _no_match -> nil
    end
  end

  defp reference_violations(_entity_type, _error), do: nil

  # The stored map is keyed by COLUMN name, so it is read back through the columns rather than by
  # making atoms of its keys. A key naming no current column belonged to a declaration that has
  # since been dropped - it reads as nothing, the way a column never set does.
  # GREATEST is the never-decrease invariant, stated in SQL: a node whose clock runs behind
  # another's cannot lower a revision that node or a client already stored, and a lowered one
  # could equal a revision an older read still holds and so read as unmoved.
  defp revisions_assignment(set_columns, stamp_placeholder) do
    entries =
      Enum.map_join(set_columns, ", ", fn column ->
        literal = column_literal(column.name)

        ~s|#{literal}, GREATEST($#{stamp_placeholder}::int8, COALESCE(("$revisions"->>#{literal})::int8, 0) + 1)|
      end)

    "\"$revisions\" = \"$revisions\" || jsonb_build_object(#{entries})"
  end

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

  # A unique index derived from a `unique: true` attribute names that attribute back, so a
  # duplicate is answered the way a value violation is - by field, in Entity.validate/2's shape.
  # Any other unique index is not ours to explain and keeps raising: a duplicate primary key is
  # a framework bug rather than something a caller did, and the grant store's index is over four
  # columns, so neither matches the single-attribute shape below.
  # The row being updated is excluded the way the unique index excludes it, so a resubmitted
  # form holding a row's own unchanged value is not refused. A create passes an id no row
  # carries yet, which excludes nothing.
  # sobelow_skip ["SQL.Query"]
  # The columns a client can write, which is what a revision is kept for - the system ones and
  # the sort-key companions are nobody's to set.
  defp settable?(column) do
    match?({:attribute, _name}, column.source) or match?({:relationship, _name}, column.source)
  end

  defp unique_value_taken?(table, column_name, value, type, id) do
    statement =
      ~s|SELECT EXISTS (SELECT 1 FROM #{qualified_table(table)} WHERE #{Mapper.quote_identifier(column_name)} = $1 AND "id" != $2)|

    params = [Codec.encode(value, type), Codec.encode(id, :uuid)]

    case Connection.query(statement, params) do
      {:ok, %Postgrex.Result{rows: [[taken?]]}} -> taken?
      {:error, error} -> raise error
    end
  end

  defp unique_violations(entity_type, %Postgrex.Error{
         postgres: %{code: :unique_violation, constraint: constraint}
       }) do
    %{columns: columns, indexes: indexes} = Map.fetch!(DB.mapping(), entity_type)

    with %{unique: true, columns: [column_name]} <- indexes[constraint],
         %{source: {:attribute, name}} <- Enum.find(columns, &(&1.name == column_name)) do
      %{name => [:unique]}
    else
      _no_match -> nil
    end
  end

  defp unique_violations(_entity_type, _error), do: nil

  defp validate_changes!(entity_type, sorted_changes, columns_by_field) do
    if sorted_changes == [] do
      raise ArgumentError,
            "invalid changes for #{inspect(entity_type)} - at least one declared attribute or to-one relationship must be changed"
    end

    unknown_names =
      sorted_changes
      |> Enum.map(fn {name, _value} -> name end)
      |> Enum.reject(&Map.has_key?(columns_by_field, &1))

    if unknown_names != [] do
      listed_names = Enum.map_join(unknown_names, ", ", &inspect/1)

      raise ArgumentError,
            "invalid changes for #{inspect(entity_type)} - only declared attributes and to-one relationships can be updated: #{listed_names}"
    end

    :ok
  end

  defp validate_entity!(entity_type, entity) do
    %{columns: columns} = Map.fetch!(DB.mapping(), entity_type)

    field_names =
      columns
      |> Enum.reject(
        &(&1.source in [:revisions, :system] or match?({:sort_key, _name}, &1.source))
      )
      |> Enum.map(&field_name/1)

    data = Map.take(entity, field_names)

    case Validator.validate(entity_type, data) do
      :ok ->
        :ok

      {:error, errors} ->
        raise ArgumentError, Validator.error_message(entity_type, data, errors)
    end
  end

  # The one place a refusal becomes an answer. A validator's map passes straight through - it was
  # keyed by field before any SQL ran - and a database error is explained against the entity type
  # the CALLER named. A constraint the mapping does not derive to one of that type's own columns
  # is not ours to explain and keeps raising, which is what holds the rows the framework writes
  # for itself in the same transaction - a create's creator grants - out of a caller's map.
  defp write_violations!(entity_type, %Postgrex.Error{} = error) do
    case unique_violations(entity_type, error) || reference_violations(entity_type, error) do
      nil -> raise error
      violations -> violations
    end
  end

  defp write_violations!(_entity_type, violations), do: violations
end
