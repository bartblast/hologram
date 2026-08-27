defmodule Hologram.Mutation.Write do
  @moduledoc false

  # One write of a batch, as the server holds it once the envelope has been parsed: the op, the
  # entity type module, the id of the row it acts on, and what the op carries - values keyed by
  # field and decoded to the terms the model declares, the amounts to move counters by, the
  # revisions the writer saw, the claim it makes, and the stamp its writer authored - or, for an
  # edge, the relationship and the row at the other end.
  #
  # Every field is already checked against THIS build's model by the time one of these exists, so
  # what reads it does not check again.

  alias Hologram.Entity
  alias Hologram.Entity.Metadata

  defstruct based_on: %{},
            claim: nil,
            data: %{},
            deltas: %{},
            entity_type: nil,
            id: nil,
            op: nil,
            relationship: nil,
            stamp: nil,
            target_id: nil

  @type t :: %__MODULE__{
          based_on: %{atom => pos_integer},
          claim: {:authorize, atom} | nil,
          data: %{atom => any},
          deltas: %{atom => integer},
          entity_type: module | nil,
          id: String.t() | nil,
          op: :create | :update | :delete | :add_relationship | :delete_relationship | nil,
          relationship: atom | nil,
          stamp: pos_integer | nil,
          target_id: String.t() | nil
        }

  @doc """
  Returns the entity struct the write's own verb would have handed the executor.

  A create builds a struct the way `Entity.new/2` does - the given id and values, with the declared
  defaults filled - and every other op names the row by id and records what it does on the struct's
  metadata, the way the pure stages record it.

  A write claiming nothing takes the operation of the verb it is: a client is never the trusted
  tier, so what a server-side verb leaves to the actor's presence - evaluate, or write raw - a
  batch always evaluates, with the anonymous semantics when nobody is signed in.
  """
  @spec to_entity(t) :: struct
  def to_entity(%__MODULE__{op: :create} = write) do
    values = Map.put(write.data, :id, write.id)
    entity = Entity.new(write.entity_type, values)

    %{entity | __meta__: %Metadata{claim: claim(write), stamp: write.stamp}}
  end

  def to_entity(%__MODULE__{op: :update} = write) do
    metadata = %Metadata{
      attribute_changes: write.data,
      attribute_deltas: write.deltas,
      claim: claim(write),
      revisions: write.based_on,
      stamp: write.stamp
    }

    entity = struct!(write.entity_type, id: write.id)

    # The values go on the struct as well as into the changes, which is what put_attribute/2,3
    # does - a caller reads back what it wrote before the write has run.
    Map.merge(entity, Map.put(write.data, :__meta__, metadata))
  end

  def to_entity(%__MODULE__{op: :delete} = write) do
    metadata = %Metadata{claim: claim(write), revisions: write.based_on, stamp: write.stamp}

    struct!(write.entity_type, id: write.id, __meta__: metadata)
  end

  def to_entity(%__MODULE__{op: op} = write) do
    edge_op = if op == :add_relationship, do: :add, else: :delete
    relationship_ops = %{{write.relationship, write.target_id} => edge_op}
    metadata = %Metadata{claim: claim(write), relationship_ops: relationship_ops}

    struct!(write.entity_type, id: write.id, __meta__: metadata)
  end

  defp claim(%__MODULE__{claim: nil, op: op}), do: {:authorize, default_operation(op)}

  defp claim(%__MODULE__{claim: claim}), do: claim

  # An edge changes the row it hangs off, so it is that row's :update - the same operation the
  # public edge verbs evaluate.
  defp default_operation(:add_relationship), do: :update

  defp default_operation(:create), do: :create

  defp default_operation(:delete), do: :delete

  defp default_operation(:delete_relationship), do: :update

  defp default_operation(:update), do: :update
end
