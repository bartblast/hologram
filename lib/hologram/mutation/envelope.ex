defmodule Hologram.Mutation.Envelope do
  @moduledoc false

  # A batch as it arrived, checked and decoded: the replica's identity and sequence number, the
  # model it was built against, and its writes as Write structs.
  #
  # Everything a client sends is checked HERE, against this build's own model - a type it does not
  # have, a field a client may not write, a value that is not that field's spelling - so what the
  # applier runs is well-formed by construction, and a broken or forged envelope is answered as a
  # bad request rather than reaching the database and crashing there.
  #
  # A refusal names the first thing wrong and stops. It is written for whoever is building a
  # client, so it says which write and which field rather than which guard.

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.Entity
  alias Hologram.Entity.Validator
  alias Hologram.Job
  alias Hologram.Mutation.Write
  alias Hologram.Reflection

  @ops "create, update, delete, add_relationship, delete_relationship"

  defstruct instance_id: nil, model_hash: nil, replica_id: nil, seq: nil, writes: []

  @type t :: %__MODULE__{
          instance_id: String.t() | nil,
          model_hash: String.t() | nil,
          replica_id: String.t() | nil,
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
         {:ok, replica_id} <- string(raw, "replica_id"),
         {:ok, seq} <- non_negative_integer(raw, "seq"),
         {:ok, model_hash} <- string(raw, "model_hash"),
         {:ok, writes} <- writes(raw) do
      {:ok,
       %__MODULE__{
         instance_id: instance_id,
         model_hash: model_hash,
         replica_id: replica_id,
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

  # The role a grant carries has to be one the resource's own type declares, which is the check
  # grant_role/3 runs before it writes. A row naming no resource type is a type-wide or a global
  # grant: there is no type here to read declarations from, and the applier refuses both outright.
  defp declared_role(%Write{op: :create, data: %{resource_type: label} = data})
       when label != nil do
    with {:ok, entity_type} <- resource_entity_type(label) do
      role = Map.get(data, :role)
      declared = Enum.map(entity_type.__roles__(), fn {name, _opts} -> name end)

      if role in declared do
        :ok
      else
        {:error, "role #{inspect(role)} is not declared on #{inspect(entity_type)}"}
      end
    end
  end

  defp declared_role(_write), do: :ok

  defp decode_based_on(revisions, entity_type) do
    fields = settable_fields(entity_type)

    Enum.reduce_while(revisions, {:ok, %{}}, &decode_revision_into(&1, &2, fields, entity_type))
  end

  defp decode_data(values, entity_type) do
    fields = settable_fields(entity_type)

    Enum.reduce_while(values, {:ok, %{}}, &decode_field_into(&1, &2, fields, entity_type))
  end

  defp decode_delta(name, amount, fields, entity_type) do
    case Map.fetch(fields, name) do
      {:ok, {field, _type}} when is_integer(amount) and amount != 0 ->
        # Bounded here because nothing downstream can: the column is judged on the value the
        # statement leaves, and an amount the column cannot hold fails the statement's own
        # parameters instead - the same range a put's value is judged against.
        if Validator.attribute_value_valid?(amount, :integer) do
          {:ok, {field, amount}}
        else
          {:error, ~s(deltas."#{name}" is out of range for an integer attribute)}
        end

      {:ok, _field} ->
        {:error, ~s(deltas."#{name}" must be a non-zero integer)}

      :error ->
        {:error,
         ~s("#{name}" is not a counter of #{inspect(entity_type)} a client can move - a counter is a required integer attribute)}
    end
  end

  defp decode_delta_into({name, amount}, {:ok, decoded}, fields, entity_type) do
    case decode_delta(name, amount, fields, entity_type) do
      {:ok, {field, value}} -> {:cont, {:ok, Map.put(decoded, field, value)}}
      {:error, message} -> {:halt, {:error, message}}
    end
  end

  defp decode_deltas(amounts, entity_type) do
    fields = movable_fields(entity_type)

    Enum.reduce_while(amounts, {:ok, %{}}, &decode_delta_into(&1, &2, fields, entity_type))
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

  # The amounts to move counters by, keyed the way data is. A write that only moves one carries no
  # data at all, so both are optional and at least one has to name a field.
  defp deltas(entry, entity_type) do
    case Map.get(entry, "deltas") do
      nil -> {:ok, %{}}
      amounts when is_map(amounts) -> decode_deltas(amounts, entity_type)
      _other -> {:error, "deltas must be an object"}
    end
  end

  # A grant's id is a function of the grant - the browser derives it from the same four columns
  # the server does - so an id that is not that derivation was not minted by an honest client.
  # Refused here rather than trusted: the applier reads a present grant back by this id, and a
  # forged one would name a row that is not the grant the columns describe. A column that is
  # absent derives to a different id and lands here too, which is a bad request where the
  # writer's own validation would be a raise.
  defp derived_id(%Write{op: :create, data: data} = write) do
    user_id = Map.get(data, :user_id)
    resource_type = Map.get(data, :resource_type)
    resource_id = Map.get(data, :resource_id)
    role = Map.get(data, :role)

    derived = RoleGrant.derive_id(user_id, resource_type, resource_id, role)

    if write.id == derived do
      :ok
    else
      {:error, "a role grant's id is derived from the grant it names"}
    end
  end

  defp derived_id(_write), do: :ok

  defp entity_type(entry) do
    case Map.get(entry, "type") do
      label when is_binary(label) -> resolve_entity_type(label)
      _other -> {:error, "type must be a string"}
    end
  end

  # A job's status, its failure record and its actor are the framework's to write - the create
  # stamps the actor, the worker records the rest - so a client is refused them by name, the way it
  # is refused a server-only attribute.
  defp framework_owned(entity_type) do
    if Reflection.job?(entity_type), do: Job.framework_attribute_names(), else: []
  end

  # Every other write may name the operation it wants evaluated. A grant's gate is fixed - the
  # grant_role and revoke_role rules of the resource's own type - so a claim here would name an
  # operation nothing consults.
  defp grant_claim(nil), do: :ok

  defp grant_claim(_claim) do
    {:error, "a role grant claims nothing - the grant_role and revoke_role rules are its gate"}
  end

  # A grant row is put in whole by grant_role and taken out whole by revoke_role, so those are the
  # two things a client naming the store has to say. An update or an edge is refused rather than
  # evaluated, because neither verb has a rule for one to be judged by.
  defp grant_op(op) when op in [:create, :delete], do: :ok

  defp grant_op(_op), do: {:error, "a role grant is created or deleted whole"}

  defp id(entry) do
    value = Map.get(entry, "id")

    if is_binary(value) and Validator.attribute_value_valid?(value, :uuid) do
      {:ok, value}
    else
      {:error, "id must be an entity id"}
    end
  end

  # The counters a client may move: the settable fields narrowed to the attributes a delta can
  # apply to - a required integer, which is the one shape that always holds a number to add to.
  defp movable_fields(entity_type) do
    optional_names =
      entity_type.__attributes__()
      |> Enum.filter(fn {_name, _type, opts} -> Keyword.get(opts, :optional) == true end)
      |> Enum.map(fn {name, _type, _opts} -> Atom.to_string(name) end)

    entity_type
    |> settable_fields()
    |> Enum.filter(fn {name, {_field, type}} ->
      type == :integer and name not in optional_names
    end)
    |> Map.new()
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

  # Only an update moves a counter: a create sets every field outright, a delete takes the row,
  # and an edge changes no column.
  defp no_deltas(entry) do
    case Map.get(entry, "deltas") do
      nil -> :ok
      amounts when amounts == %{} -> :ok
      _other -> {:error, "only an update carries deltas"}
    end
  end

  # A field set and moved by one write would be assigned twice in one statement, and the two say
  # different things about the same column.
  defp no_overlap(data, deltas) do
    both =
      data
      |> Map.keys()
      |> Enum.filter(&Map.has_key?(deltas, &1))
      |> Enum.sort()

    case both do
      [] -> :ok
      [name | _rest] -> {:error, ~s("#{name}" is both set and moved by one write)}
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
         :ok <- no_deltas(entry),
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
         :ok <- no_deltas(entry),
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
         {:ok, data} <- update_data(entry, entity_type),
         {:ok, deltas} <- deltas(entry, entity_type),
         :ok <- some_change(data, deltas),
         :ok <- no_overlap(data, deltas),
         {:ok, based_on} <- based_on(entry, entity_type),
         {:ok, claim} <- claim(entry),
         {:ok, stamp} <- stamp(entry) do
      {:ok,
       %Write{
         based_on: based_on,
         claim: claim,
         data: data,
         deltas: deltas,
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
         :ok <- no_deltas(entry),
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
    parsed =
      case Map.get(entry, "op") do
        "add_relationship" -> parse_edge(entry, :add_relationship)
        "create" -> parse_create(entry)
        "delete" -> parse_delete(entry)
        "delete_relationship" -> parse_edge(entry, :delete_relationship)
        "update" -> parse_update(entry)
        _other -> {:error, "op must be one of #{@ops}"}
      end

    with {:ok, write} <- parsed do
      validate_grant_write(write)
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

  # An enum decodes to whatever atom it spells rather than to a declared value - membership is the
  # write's to judge, as the label of any other enum is - but a grant's label has to resolve to a
  # module HERE, because the declared-role check reads that module's declarations. A label naming
  # no table is therefore answered the way an unknown write type is, rather than left to a layer
  # that raises instead of answering: the grant path validates through insert_if_absent, whose
  # refusal is a broken invariant rather than something a client can be told.
  defp resource_entity_type(label) do
    case RoleGrant.entity_type(label) do
      nil -> {:error, ~s(resource_type "#{label}" is not an entity type of this build)}
      entity_type -> {:ok, entity_type}
    end
  end

  defp some_change(data, deltas) when data == %{} and deltas == %{} do
    {:error, "an update must change at least one field"}
  end

  defp some_change(_data, _deltas), do: :ok

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
    withheld = Entity.server_only_attribute_names(entity_type) ++ framework_owned(entity_type)

    attributes =
      entity_type.__attributes__()
      |> Enum.reject(fn {name, _type, _opts} -> name in withheld end)
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

  # An update carrying only deltas has no data at all, which reads as no values rather than as a
  # malformed entry - a create's still must be there.
  defp update_data(entry, entity_type) do
    case Map.get(entry, "data") do
      nil -> {:ok, %{}}
      _values -> data(entry, entity_type)
    end
  end

  # The grant store is written through Auth.grant_role and Auth.revoke_role, never through the
  # writer, so a batch naming it is putting one grant in or taking one out. What it cannot be is
  # refused here, where whoever is building a client is told what they built - leaving the applier
  # the two shapes it routes, and its own refusals about authority rather than about shape.
  defp validate_grant_write(%Write{entity_type: RoleGrant} = write) do
    with :ok <- grant_op(write.op),
         :ok <- grant_claim(write.claim),
         :ok <- declared_role(write),
         :ok <- derived_id(write) do
      {:ok, write}
    end
  end

  defp validate_grant_write(write), do: {:ok, write}

  defp writes(raw) do
    case Map.get(raw, "writes") do
      entries when is_list(entries) -> parse_writes(entries)
      _other -> {:error, "writes must be a list"}
    end
  end
end
