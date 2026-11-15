defmodule Hologram.Sync.Fill do
  @moduledoc false

  # What a browser arriving with nothing is sent of one entity type: every row of it its user may
  # read, read through the type's read rules the way the server render reads, rather than through
  # the queries pages run. Every row a user may read is what the browser holds once it is filled,
  # so a type is either sent whole or not at all - and once it has been, the browser can answer any
  # query over it from what it holds.
  #
  # A row travels with the target ids of its to-many relationships and of its inverses of a
  # to-many, which is how the wire states a set (see `Hologram.Sync.WireData.row/1`): the rows of
  # the other side are sent as their own type's rows, and the set is the fact pairing the two.
  # Each set holds only the targets the user may read, since an include is read through the
  # target type's own read rules. A to-one adds nothing beside its reference field, and an inverse
  # of a to-one nothing beside the reference fields of its rows. A set whose targets are of a type
  # sync sends nothing of is left out: it would name rows the browser never gets.
  #
  # The rows and the number saying how far the browser's own batches are in them are read in one
  # snapshot. A frame's number lands the browser's pending batches on the rows that frame carries,
  # so a number read a moment apart from the rows can say a batch is missing from rows that hold
  # it - and the browser applies it a second time - or say one is in rows read before it committed.

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.QueryRunner
  alias Hologram.Entity
  alias Hologram.Mutation.Record
  alias Hologram.Query
  alias Hologram.Query.Stage

  @doc """
  Returns the rows of the given entity type the given user may read, as the fill sends them (see
  `term/2`), with the highest sequence number at which the given replica has had a batch confirmed,
  both read in one snapshot.

  A nil user reads as a visitor, through the read rules, never through the trusted tier. A nil
  replica has no number.
  """
  @spec read(module, String.t() | nil, String.t() | nil, list(module)) ::
          {list(struct), non_neg_integer | nil}
  def read(entity_type, actor_user_id, replica_id, synced_types) do
    term = term(entity_type, synced_types)

    {:ok, read} =
      Connection.snapshot(fn ->
        applied_seq = replica_id && Record.highest_confirmed_seq(replica_id)
        rows = QueryRunner.run_policied(term, DB.mapping(), actor_user_id)

        {rows, applied_seq}
      end)

    read
  end

  @doc """
  Returns the query term the fill reads the given entity type with: every row of it, with every
  to-many relationship and every inverse of a to-many whose target is one of the given synced
  types included.
  """
  @spec term(module, list(module)) :: Query.t()
  def term(entity_type, synced_types) do
    synced = MapSet.new(synced_types)

    entity_type
    |> set_names(synced)
    |> Enum.reduce(Stage.normalize(entity_type), &Stage.include(&2, &1))
  end

  defp set_names(entity_type, synced) do
    to_many =
      for {name, [target], _opts} <- entity_type.__relationships__(),
          MapSet.member?(synced, target),
          do: name

    to_many_inverses =
      for {name, _type, _opts} <- entity_type.__inverse_relationships__(),
          inverse = Entity.inverse_relationship(entity_type, name),
          not inverse.reference?,
          MapSet.member?(synced, inverse.target),
          do: name

    Enum.sort(to_many ++ to_many_inverses)
  end
end
