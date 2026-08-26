defmodule Hologram.Mutation.Envelope do
  @moduledoc false

  # A batch as it arrived, checked and decoded: the client's identity and sequence number, the
  # model it was built against, and its writes as Write structs.
  #
  # Everything a client sends is checked HERE, against this build's own model - a type it does not
  # have, a field a client may not write, a value that is not that field's spelling - so what the
  # applier runs is well-formed by construction, and a broken or forged envelope is answered as a
  # bad request rather than reaching the database and crashing there.
  #
  # A refusal names the first thing wrong and stops. It is written for whoever is building a
  # client, so it says which write and which field rather than which guard.

  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.Entity
  alias Hologram.Entity.Validator
  alias Hologram.Mutation.Write

  @ops "create, update, delete, add_relationship, delete_relationship"

  defstruct client_id: nil, instance_id: nil, model_hash: nil, seq: nil, writes: []

  @type t :: %__MODULE__{
          client_id: String.t() | nil,
          instance_id: String.t() | nil,
          model_hash: String.t() | nil,
          seq: non_neg_integer | nil,
          writes: list(Write.t())
        }

  @doc """
  Parses the given decoded JSON object into an envelope, or returns the first thing wrong with it
  as a message whoever is building a client can act on.
  """
  @spec parse(map) :: {:ok, t} | {:error, String.t()}
  def parse(raw) do
    with {:ok, instance_id} <- string(raw, "instance_id"),
         {:ok, client_id} <- string(raw, "client_id"),
         {:ok, seq} <- non_negative_integer(raw, "seq"),
         {:ok, model_hash} <- string(raw, "model_hash"),
         {:ok, writes} <- writes(raw) do
      {:ok,
       %__MODULE__{
         client_id: client_id,
         instance_id: instance_id,
         model_hash: model_hash,
         seq: seq,
         writes: writes
       }}
    end
  end

  # What the writer saw: the revision of each column the write touches, as of when it decided. An
  # entry missing altogether reads as no revisions, which is a write based on nothing having been
  # seen - the merge answers it the same way it answers a column the row has never had set.
  defp based_on(entry, entity_type) do
    case Map.get(entry, "based_on") do
      nil -> {:ok, %{}}
      revisions when is_map(revisions) -> decode_based_on(revisions, entity_type)
      _other -> {:error, "based_on must be an object"}
    end
  end

  defp authorize_claim(operation) do
    {:ok, {:authorize, String.to_existing_atom(operation)}}
  rescue
    ArgumentError -> {:error, "claim names no operation this build declares"}
  end

  defp claim(entry) do
    case Map.get(entry, "claim") do
      nil ->
        {:ok, nil}

      ["authorize", operation] when is_binary(operation) ->
        authorize_claim(operation)

      # A claim is a request, never a grant, and the server's own authority is not a client's to
      # request - so this is refused by name rather than evaluated and denied.
      "trust" ->
        {:error, "trust is the server's authority - a client cannot claim it"}

      _other ->
        {:error, ~s(claim must be null or ["authorize", operation])}
    end
  end

  defp data(entry, entity_type) do
    case Map.get(entry, "data") do
      values when is_map(values) -> decode_data(values, entity_type)
      _other -> {:error, "data must be an object"}
    end
  end

  defp decode_based_on(revisions, entity_type) do
    fields = settable_fields(entity_type)

    Enum.reduce_while(revisions, {:ok, %{}}, &decode_revision_into(&1, &2, fields, entity_type))
  end

  defp decode_data(values, entity_type) do
    fields = settable_fields(entity_type)

    Enum.reduce_while(values, {:ok, %{}}, &decode_field_into(&1, &2, fields, entity_type))
  end

  defp decode_field(name, value, fields, entity_type) do
    case Map.fetch(fields, name) do
      {:ok, {field, type}} ->
        decode_value(name, value, field, type)

      :error ->
        {:error, ~s("#{name}" is not a field of #{inspect(entity_type)} a client can write)}
    end
  end

  defp decode_field_into({name, value}, {:ok, decoded}, fields, entity_type) do
    case decode_field(name, value, fields, entity_type) do
      {:ok, {field, value}} -> {:cont, {:ok, Map.put(decoded, field, value)}}
      {:error, message} -> {:halt, {:error, message}}
    end
  end

  defp decode_revision(name, revision, fields, entity_type) do
    case Map.fetch(fields, name) do
      {:ok, {field, _type}} when is_integer(revision) and revision > 0 ->
        {:ok, {field, revision}}

      {:ok, _field} ->
        {:error, ~s(based_on."#{name}" must be a positive integer)}

      :error ->
        {:error, ~s("#{name}" is not a field of #{inspect(entity_type)} a client can write)}
    end
  end

  defp decode_revision_into({name, revision}, {:ok, decoded}, fields, entity_type) do
    case decode_revision(name, revision, fields, entity_type) do
      {:ok, {field, value}} -> {:cont, {:ok, Map.put(decoded, field, value)}}
      {:error, message} -> {:halt, {:error, message}}
    end
  end

  defp decode_value(name, value, field, type) do
    case Codec.decode_json(value, type) do
      {:ok, decoded} -> {:ok, {field, decoded}}
      :error -> {:error, ~s("#{name}" is not a valid #{type_word(type)})}
    end
  end

  defp entity_type(entry) do
    case Map.get(entry, "type") do
      label when is_binary(label) -> resolve_entity_type(label)
      _other -> {:error, "type must be a string"}
    end
  end

  defp id(entry) do
    value = Map.get(entry, "id")

    if is_binary(value) and Validator.attribute_value_valid?(value, :uuid) do
      {:ok, value}
    else
      {:error, "id must be an entity id"}
    end
  end

  # A delete takes the whole row, so there is nothing for it to carry values for - one that does
  # was built by something that does not know what a delete is.
  defp no_data(entry) do
    case Map.get(entry, "data") do
      nil -> :ok
      values when values == %{} -> :ok
      _other -> {:error, "a delete carries no data"}
    end
  end

  # An edge is a fact in a join table rather than a column of a row, so there is nothing for a
  # revision to be kept against - adding and removing the same pair commute, whoever wrote them.
  defp no_stamp(entry) do
    case Map.get(entry, "stamp") do
      nil -> :ok
      _other -> {:error, "an edge carries no stamp"}
    end
  end

  defp non_negative_integer(raw, key) do
    case Map.get(raw, key) do
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _other -> {:error, "#{key} must be a non-negative integer"}
    end
  end

  defp parse_create(entry) do
    with {:ok, entity_type} <- entity_type(entry),
         {:ok, id} <- id(entry),
         {:ok, data} <- data(entry, entity_type),
         {:ok, claim} <- claim(entry),
         {:ok, stamp} <- stamp(entry) do
      {:ok,
       %Write{
         claim: claim,
         data: data,
         entity_type: entity_type,
         id: id,
         op: :create,
         stamp: stamp
       }}
    end
  end

  defp parse_delete(entry) do
    with {:ok, entity_type} <- entity_type(entry),
         {:ok, id} <- id(entry),
         :ok <- no_data(entry),
         {:ok, based_on} <- based_on(entry, entity_type),
         {:ok, claim} <- claim(entry),
         {:ok, stamp} <- stamp(entry) do
      {:ok,
       %Write{
         based_on: based_on,
         claim: claim,
         entity_type: entity_type,
         id: id,
         op: :delete,
         stamp: stamp
       }}
    end
  end

  defp parse_update(entry) do
    with {:ok, entity_type} <- entity_type(entry),
         {:ok, id} <- id(entry),
         {:ok, data} <- data(entry, entity_type),
         :ok <- some_data(data),
         {:ok, based_on} <- based_on(entry, entity_type),
         {:ok, claim} <- claim(entry),
         {:ok, stamp} <- stamp(entry) do
      {:ok,
       %Write{
         based_on: based_on,
         claim: claim,
         data: data,
         entity_type: entity_type,
         id: id,
         op: :update,
         stamp: stamp
       }}
    end
  end

  defp parse_edge(entry, op) do
    with {:ok, entity_type} <- entity_type(entry),
         {:ok, id} <- id(entry),
         {:ok, relationship} <- relationship(entry, entity_type),
         {:ok, target_id} <- target_id(entry),
         :ok <- no_stamp(entry),
         {:ok, claim} <- claim(entry) do
      {:ok,
       %Write{
         claim: claim,
         entity_type: entity_type,
         id: id,
         op: op,
         relationship: relationship,
         target_id: target_id
       }}
    end
  end

  defp parse_write(entry) when is_map(entry) do
    case Map.get(entry, "op") do
      "add_relationship" -> parse_edge(entry, :add_relationship)
      "create" -> parse_create(entry)
      "delete" -> parse_delete(entry)
      "delete_relationship" -> parse_edge(entry, :delete_relationship)
      "update" -> parse_update(entry)
      _other -> {:error, "op must be one of #{@ops}"}
    end
  end

  defp parse_write(_entry), do: {:error, "a write must be an object"}

  defp parse_write_into({entry, index}, {:ok, writes}) do
    case parse_write(entry) do
      {:ok, write} -> {:cont, {:ok, [write | writes]}}
      {:error, message} -> {:halt, {:error, "write #{index}: #{message}"}}
    end
  end

  defp parse_writes(entries) do
    result =
      entries
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, &parse_write_into/2)

    case result do
      {:ok, writes} -> {:ok, Enum.reverse(writes)}
      {:error, message} -> {:error, message}
    end
  end

  defp relationship(entry, entity_type) do
    case Map.get(entry, "relationship") do
      name when is_binary(name) -> resolve_relationship(name, entity_type)
      _other -> {:error, "relationship must be a string"}
    end
  end

  defp resolve_entity_type(label) do
    entity_type = String.to_existing_atom("Elixir." <> label)

    if Map.has_key?(DB.mapping(), entity_type) do
      {:ok, entity_type}
    else
      {:error, unknown_type_message(label)}
    end
  rescue
    # A label naming no atom this build ever compiled is the same answer as one naming an atom
    # that is not an entity type: a client is told what this build does not have, not how it
    # failed to look it up.
    ArgumentError -> {:error, unknown_type_message(label)}
  end

  defp some_data(data) when data == %{}, do: {:error, "an update must change at least one field"}

  defp some_data(_data), do: :ok

  # A to-ONE is not an edge: it is set through its reference field like any other value, so naming
  # one here is refused the same way naming no relationship at all is.
  defp resolve_relationship(name, entity_type) do
    to_many =
      entity_type.__relationships__()
      |> Enum.filter(fn {_name, type, _opts} -> is_list(type) end)
      |> Enum.map(fn {relationship_name, _type, _opts} -> relationship_name end)

    case Enum.find(to_many, &(Atom.to_string(&1) == name)) do
      nil ->
        {:error, ~s("#{name}" is not a to-many relationship of #{inspect(entity_type)})}

      relationship ->
        {:ok, relationship}
    end
  end

  # The fields a client may write: the declared attributes minus the server-only ones, which a
  # client is never told exist, and the to-one references under their id spelling.
  defp settable_fields(entity_type) do
    server_only = Entity.server_only_attribute_names(entity_type)

    attributes =
      entity_type.__attributes__()
      |> Enum.reject(fn {name, _type, _opts} -> name in server_only end)
      |> Map.new(fn {name, type, _opts} -> {Atom.to_string(name), {name, type}} end)

    # The reference field's atom already exists - the entity macro puts it on the struct - so this
    # asks for it rather than creating one, the way every other reader of a reference field does.
    references =
      entity_type.__relationships__()
      |> Enum.reject(fn {_name, type, _opts} -> is_list(type) end)
      |> Map.new(fn {name, _type, _opts} ->
        field = "#{name}_id"

        {field, {String.to_existing_atom(field), :uuid}}
      end)

    Map.merge(attributes, references)
  end

  defp stamp(entry) do
    case Map.get(entry, "stamp") do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _other -> {:error, "stamp must be a positive integer"}
    end
  end

  defp string(raw, key) do
    case Map.get(raw, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, "#{key} must be a string"}
    end
  end

  defp target_id(entry) do
    value = Map.get(entry, "target_id")

    if is_binary(value) and Validator.attribute_value_valid?(value, :uuid) do
      {:ok, value}
    else
      {:error, "target_id must be an entity id"}
    end
  end

  defp type_word(:enum), do: "enum value"

  defp type_word(:uuid), do: "entity id"

  defp type_word(type), do: Atom.to_string(type)

  defp unknown_type_message(label) do
    ~s(type "#{label}" is not an entity type of this build)
  end

  defp writes(raw) do
    case Map.get(raw, "writes") do
      entries when is_list(entries) -> parse_writes(entries)
      _other -> {:error, "writes must be a list"}
    end
  end
end
