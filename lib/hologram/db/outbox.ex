defmodule Hologram.DB.Outbox do
  @moduledoc false

  # The effect log: one row per entity-level effect, appended in the transaction that caused it,
  # so a write and the record of it either both land or neither does. What the rows are read for
  # is which entity types and attributes a transaction touched - the values a client is sent come
  # from reading the rows themselves afresh, never from here.

  alias Hologram.Auth.Context
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Entity
  alias Hologram.Entity.Model

  @channel "hologram_outbox"

  @columns ["op", "type", "entity_id", "data", "model_hash", "actor_id"]

  @data_ops [:patch_entity, :put_entity]

  @relationship_ops [:add_relationship, :del_relationship]

  @doc """
  Appends the given effects to the outbox in the caller's transaction, and wakes the dispatchers
  listening for them. Appending nothing does nothing.

  An effect names its `:op`, the `:entity_type` and `:entity_id` it happened to, and what the op
  carries: `:data` for `:put_entity` (every attribute) and `:patch_entity` (the changed ones),
  `:relationship` and `:target_id` for the relationship ops, nothing for `:del_entity`.

  Values of attributes declared server_only are dropped rather than stored - the log outlives the
  transaction by as long as its retention window, and nothing in it may hold what never leaves
  the server. The acting user is read from the ambient context, so writes made by the framework
  itself, which have no actor, record none.
  """
  @spec append(list(map)) :: :ok
  def append([]), do: :ok

  # sobelow_skip ["SQL.Query"]
  def append(effects) do
    model_hash = Model.hash()
    actor_id = Codec.encode(Context.actor_user_id(), :uuid)

    values = Enum.flat_map(effects, &row(&1, model_hash, actor_id))

    column_list = Enum.map_join(@columns, ", ", &Mapper.quote_identifier/1)
    row_list = row_placeholders(length(effects))

    statement =
      "INSERT INTO #{qualified_table()} (#{column_list}) VALUES #{row_list}"

    {:ok, _result} = Connection.query(statement, values)

    notify()
  end

  defp attribute_type(entity_type, name) do
    definitions = entity_type.__attributes__() ++ entity_type.__system_attributes__()

    case Enum.find(definitions, fn {definition_name, _type, _opts} -> definition_name == name end) do
      # A name matching no attribute definition is a to-one reference field, and every reference
      # column carries the entity id type.
      nil -> :uuid
      {_name, type, _opts} -> type
    end
  end

  defp data(%{op: op, entity_type: entity_type, data: data}) when op in @data_ops do
    server_only = Entity.server_only_attribute_names(entity_type)

    data
    |> Map.drop(server_only)
    |> Map.new(fn {name, value} ->
      {name, Codec.encode_json(value, attribute_type(entity_type, name))}
    end)
  end

  defp data(%{op: op, relationship: relationship, target_id: target_id})
       when op in @relationship_ops do
    %{relationship: relationship, target_id: target_id}
  end

  defp data(%{op: :del_entity}), do: nil

  defp notify do
    {:ok, _result} = Connection.query("SELECT pg_notify($1, '')", [@channel])

    :ok
  end

  defp qualified_table do
    "#{Mapper.quote_identifier("hologram_system")}.#{Mapper.quote_identifier("outbox")}"
  end

  defp row(
         %{op: op, entity_type: entity_type, entity_id: entity_id} = effect,
         model_hash,
         actor_id
       ) do
    [
      Atom.to_string(op),
      Codec.encode_enum_value(entity_type),
      Codec.encode(entity_id, :uuid),
      data(effect),
      model_hash,
      actor_id
    ]
  end

  defp row_placeholders(count) do
    column_count = length(@columns)

    Enum.map_join(0..(count - 1), ", ", fn index ->
      placeholders =
        Enum.map_join(1..column_count, ", ", &"$#{index * column_count + &1}")

      "(#{placeholders})"
    end)
  end
end
