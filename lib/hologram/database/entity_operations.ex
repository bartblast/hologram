defmodule Hologram.Database.EntityOperations do
  @moduledoc false

  # The entity row and edge operations of the database gateway. The public surface lives
  # on Hologram.Database - these functions back its delegates, which also carry the docs.

  # SQL statements in this module interpolate ONLY framework-derived identifiers (always
  # through Mapper.quote_identifier/1) and $n placeholders - every value travels as a bound
  # param. The sobelow_skip markers on the emitting functions record that invariant.

  alias Hologram.Database
  alias Hologram.Database.Codec
  alias Hologram.Database.Connection
  alias Hologram.Database.Mapper

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

    case Connection.query(statement, [encoded_id, encoded_target_id]) do
      {:ok, _result} -> :ok
      {:error, error} -> raise error
    end
  end

  @doc false
  @spec create(struct) :: struct
  # sobelow_skip ["SQL.Query"]
  def create(entity) do
    entity_type = entity.__struct__
    %{table: table, columns: columns} = Map.fetch!(Database.mapping(), entity_type)

    now = DateTime.utc_now(:microsecond)
    stamped_entity = %{entity | created_at: now, updated_at: now}

    encoded_values =
      Enum.map(columns, fn column ->
        stamped_entity
        |> Map.fetch!(field_name(column))
        |> Codec.encode(column.type)
      end)

    column_list = Enum.map_join(columns, ", ", &Mapper.quote_identifier(&1.name))
    placeholder_list = Enum.map_join(1..length(columns), ", ", &"$#{&1}")

    statement =
      "INSERT INTO #{qualified_table(table)} (#{column_list}) VALUES (#{placeholder_list})"

    case Connection.query(statement, encoded_values) do
      {:ok, _result} -> stamped_entity
      {:error, error} -> raise error
    end
  end

  @doc false
  @spec delete(module, String.t()) :: :ok | {:error, {:restricted, map}}
  def delete(entity_type, id) do
    %{table: table, join_tables: join_tables} = Map.fetch!(Database.mapping(), entity_type)

    encoded_id = Codec.encode(id, :uuid)

    transaction_result =
      Connection.transaction(fn ->
        delete_outgoing_edges(join_tables, encoded_id)
        delete_entity_row(entity_type, table, id, encoded_id)
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

    case Connection.query(statement, [encoded_id, encoded_target_id]) do
      {:ok, _result} -> :ok
      {:error, error} -> raise error
    end
  end

  @doc false
  @spec get(module, String.t()) :: struct | nil
  # sobelow_skip ["SQL.Query"]
  def get(entity_type, id) do
    %{table: table, columns: columns} = Map.fetch!(Database.mapping(), entity_type)

    column_list = Enum.map_join(columns, ", ", &Mapper.quote_identifier(&1.name))
    statement = ~s|SELECT #{column_list} FROM #{qualified_table(table)} WHERE "id" = $1|

    encoded_id = Codec.encode(id, :uuid)

    case Connection.query(statement, [encoded_id]) do
      {:ok, %Postgrex.Result{rows: []}} ->
        nil

      {:ok, %Postgrex.Result{rows: [row]}} ->
        fields =
          columns
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
  @spec update(module, String.t(), map | keyword) :: :ok
  # sobelow_skip ["SQL.Query"]
  def update(entity_type, id, changes) do
    %{table: table, columns: columns} = Map.fetch!(Database.mapping(), entity_type)

    columns_by_field =
      columns
      |> Enum.reject(&(&1.source == :system))
      |> Map.new(&{field_name(&1), &1})

    sorted_changes =
      changes
      |> Map.new()
      |> Enum.sort()

    validate_changed_names!(entity_type, sorted_changes, columns_by_field)

    set_list =
      sorted_changes
      |> Enum.with_index(1)
      |> Enum.map_join(", ", fn {{name, _value}, index} ->
        "#{Mapper.quote_identifier(columns_by_field[name].name)} = $#{index}"
      end)

    updated_at_placeholder = length(sorted_changes) + 1
    id_placeholder = length(sorted_changes) + 2

    statement =
      ~s|UPDATE #{qualified_table(table)} SET #{set_list}, "updated_at" = $#{updated_at_placeholder} WHERE "id" = $#{id_placeholder}|

    changed_values =
      Enum.map(sorted_changes, fn {name, value} ->
        Codec.encode(value, columns_by_field[name].type)
      end)

    updated_at = DateTime.utc_now(:microsecond)
    encoded_updated_at = Codec.encode(updated_at, :datetime)
    encoded_id = Codec.encode(id, :uuid)

    case Connection.query(statement, changed_values ++ [encoded_updated_at, encoded_id]) do
      {:ok, %Postgrex.Result{num_rows: 1}} ->
        :ok

      {:ok, %Postgrex.Result{num_rows: 0}} ->
        raise ArgumentError,
              "cannot update #{inspect(entity_type)} - no entity with id #{inspect(id)}"

      {:error, error} ->
        raise error
    end
  end

  # sobelow_skip ["SQL.Query"]
  defp delete_entity_row(entity_type, table, id, encoded_id) do
    statement = ~s|DELETE FROM #{qualified_table(table)} WHERE "id" = $1|

    case Connection.query(statement, [encoded_id]) do
      {:ok, _result} ->
        :ok

      {:error, %Postgrex.Error{postgres: %{code: :foreign_key_violation}}} ->
        Connection.rollback({:restricted, %{entity_type: entity_type, id: id}})

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

  defp fetch_join_table!(entity_type, relationship_name) do
    %{join_tables: join_tables} = Map.fetch!(Database.mapping(), entity_type)

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

  defp field_name(%{source: {:relationship, name}}), do: name

  defp qualified_table(table) do
    "#{Mapper.quote_identifier(@data_schema)}.#{Mapper.quote_identifier(table)}"
  end

  defp validate_changed_names!(entity_type, sorted_changes, columns_by_field) do
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
end
