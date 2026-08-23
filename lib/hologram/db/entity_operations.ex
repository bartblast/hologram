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
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.DB.Outbox
  alias Hologram.DB.SortKey
  alias Hologram.Entity
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
    # refuse, and what the values earned is merged with the uniqueness a query can still see.
    case Entity.validate(entity) do
      :ok ->
        # The transaction's own shape is the contract: its value is the stamped entity, and the
        # violations a duplicate rolls back with are its reason.
        Connection.transaction(fn ->
          {stamped_entity, _result} = insert(entity, "")

          Outbox.append([put_effect(stamped_entity)])

          entity
          |> creator_grants()
          |> Enum.each(&create_if_absent/1)

          stamped_entity
        end)

      {:error, violations} ->
        values = Map.from_struct(entity)

        {:error, advisory_unique_violations(entity_type, values, entity.id, violations)}
    end
  end

  @doc false
  @spec create_if_absent(struct) :: :ok
  def create_if_absent(entity) do
    # The framework writes its own grants through this path, so an invalid one is a broken
    # invariant rather than something a caller can answer - it raises where create/1 returns.
    validate_entity!(entity.__struct__, entity)

    {:ok, :ok} =
      Connection.transaction(fn ->
        {stamped_entity, result} = insert(entity, " ON CONFLICT DO NOTHING")

        # A row that was already there is not a change, and the conflicting insert wrote
        # nothing - an effect recorded for it would be a change clients never saw happen.
        if result.num_rows == 1 do
          Outbox.append([put_effect(stamped_entity)])
        end

        :ok
      end)

    :ok
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

  @doc false
  @spec get(module, String.t()) :: struct | nil
  # sobelow_skip ["SQL.Query"]
  def get(entity_type, id) do
    validate_id!(id)

    %{table: table, columns: columns} = Map.fetch!(DB.mapping(), entity_type)

    persisted_columns = Enum.reject(columns, &match?({:sort_key, _name}, &1.source))

    column_list = Enum.map_join(persisted_columns, ", ", &Mapper.quote_identifier(&1.name))
    statement = ~s|SELECT #{column_list} FROM #{qualified_table(table)} WHERE "id" = $1|

    encoded_id = Codec.encode(id, :uuid)

    case Connection.query(statement, [encoded_id]) do
      {:ok, %Postgrex.Result{rows: []}} ->
        nil

      {:ok, %Postgrex.Result{rows: [row]}} ->
        fields =
          persisted_columns
          |> Enum.zip(row)
          |> Enum.map(fn {column, value} ->
            {field_name(column), Codec.decode(value, column.type)}
          end)

        struct!(entity_type, fields)

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
      |> Enum.reject(&(&1.source == :system or match?({:sort_key, _name}, &1.source)))
      |> Map.new(&{field_name(&1), &1})

    changes_map = Map.new(changes)
    sorted_changes = Enum.sort(changes_map)

    validate_changes!(entity_type, sorted_changes, columns_by_field)

    # Values are judged before the statement is built - nothing is written for changes the
    # declarations already refuse, and what they earned is merged with the uniqueness a query
    # can still see.
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

        updated_at_placeholder = length(set_entries) + 1
        id_placeholder = length(set_entries) + 2

        statement =
          ~s|UPDATE #{qualified_table(table)} SET #{set_list}, "updated_at" = $#{updated_at_placeholder} WHERE "id" = $#{id_placeholder}|

        changed_values = Enum.map(set_entries, fn {_column, value} -> value end)

        updated_at = DateTime.utc_now(:microsecond)
        encoded_updated_at = Codec.encode(updated_at, :datetime)
        encoded_id = Codec.encode(id, :uuid)

        params = changed_values ++ [encoded_updated_at, encoded_id]

        # The stamp travels with the changes: every update moves updated_at, and a client holding
        # the row holds that too. The sort-key companions do not - they are derived from the values
        # beside them, and a reader recomputes them rather than being told.
        data = Map.put(changes_map, :updated_at, updated_at)

        # The transaction's reason is the violations map, the way create/1's is - a duplicate rolls
        # the update back rather than raising.
        transaction_result =
          Connection.transaction(fn ->
            run_update!(statement, params, entity_type, id, data)
          end)

        case transaction_result do
          {:ok, _appended} -> :ok
          {:error, violations} -> {:error, violations}
        end

      {:error, violations} ->
        {:error, advisory_unique_violations(entity_type, changes_map, id, violations)}
    end
  end

  # A unique attribute is worth asking about only when the value could be compared at all: a
  # field carrying its own violation is not comparable, and nil never conflicts.
  defp advisory_candidate?({name, _type, opts}, values, violations) do
    Keyword.get(opts, :unique) == true and not Map.has_key?(violations, name) and
      not is_nil(values[name])
  end

  # Asked only when no write could be attempted - once the values pass, the write itself is the
  # uniqueness check and its answer is the one that counts. Advisory by nature: what is taken
  # now may be free by the resubmit, and the resubmit is answered by the write.
  defp advisory_unique_violations(entity_type, values, id, violations) do
    %{table: table, columns: columns} = Map.fetch!(DB.mapping(), entity_type)

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
    stamped_entity = %{entity | created_at: now, updated_at: now}

    encoded_values = Enum.map(columns, &encoded_column_value(stamped_entity, &1))

    column_list = Enum.map_join(columns, ", ", &Mapper.quote_identifier(&1.name))
    placeholder_list = Enum.map_join(1..length(columns), ", ", &"$#{&1}")

    statement =
      "INSERT INTO #{qualified_table(table)} (#{column_list}) " <>
        "VALUES (#{placeholder_list})#{conflict_clause}"

    case Connection.query(statement, encoded_values) do
      {:ok, result} ->
        {stamped_entity, result}

      {:error, error} ->
        case unique_violations(entity_type, error) do
          nil -> raise error
          violations -> Connection.rollback(violations)
        end
    end
  end

  # What the entity is, as the effect log records it: every column the row carries except the
  # sort-key companions, which are derived from the values beside them rather than written.
  defp put_effect(entity) do
    entity_type = entity.__struct__
    %{columns: columns} = Map.fetch!(DB.mapping(), entity_type)

    data =
      columns
      |> Enum.reject(&match?({:sort_key, _name}, &1.source))
      |> Map.new(fn column ->
        name = field_name(column)

        {name, Map.fetch!(entity, name)}
      end)

    %{op: :put_entity, entity_type: entity_type, entity_id: entity.id, data: data}
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

  defp run_update!(statement, params, entity_type, id, data) do
    case Connection.query(statement, params) do
      {:ok, %Postgrex.Result{num_rows: 1}} ->
        Outbox.append([
          %{op: :patch_entity, entity_type: entity_type, entity_id: id, data: data}
        ])

      {:ok, %Postgrex.Result{num_rows: 0}} ->
        raise ArgumentError,
              "cannot update #{inspect(entity_type)} - no entity with id #{inspect(id)}"

      {:error, error} ->
        case unique_violations(entity_type, error) do
          nil -> raise error
          violations -> Connection.rollback(violations)
        end
    end
  end

  defp qualified_table(table) do
    "#{Mapper.quote_identifier(@data_schema)}.#{Mapper.quote_identifier(table)}"
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
      |> Enum.reject(&(&1.source == :system or match?({:sort_key, _name}, &1.source)))
      |> Enum.map(&field_name/1)

    data = Map.take(entity, field_names)

    case Validator.validate(entity_type, data) do
      :ok ->
        :ok

      {:error, errors} ->
        raise ArgumentError, Validator.error_message(entity_type, data, errors)
    end
  end

  defp validate_id!(id) do
    if not Validator.attribute_value_valid?(id, :uuid) do
      raise ArgumentError,
            "invalid id #{inspect(id)} for get - entity ids are canonical lowercase 8-4-4-4-12 UUID strings"
    end
  end
end
