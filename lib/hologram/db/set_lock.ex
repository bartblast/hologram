defmodule Hologram.DB.SetLock do
  @moduledoc false

  # A write let through by a none or an all rests on every row of a set, the rows not there yet
  # included. Share-locking the rows it read keeps them as they were until it commits, but a row
  # joining the set is a row nobody read. When the write holds the set's owner row FOR UPDATE - a
  # delete or an update of the owner itself - the joining row's foreign key check waits on it
  # anyway. When it reached the owner through a share-locked read - a task's update resting on
  # none(member <- project.members, ...) - nothing stops a member being inserted into that project
  # between the evaluation and the write, under read committed.
  #
  # So the set is locked by name. The write resting on the answer takes an advisory transaction lock
  # named by the row the set belongs to, exclusively, before it reads the set - and every write that
  # can put a row into such a set takes the same lock, shared, before it writes. Writes entering a
  # set never wait for each other, a write resting on the set waits for the ones already entering it
  # to commit and reads what they wrote, and the ones arriving after wait for it. Writes resting on
  # one set wait for each other in turn, which is what the answer costs. Which sets need this is read
  # off the rules (see Hologram.Policy.locked_set_links/0), so a write to a type no such rule reads
  # takes nothing.
  #
  # A write entering a set first takes the key share locks its own foreign key checks take - on the
  # owner and on every other row it references - and only then the advisory locks, the order the
  # resting write takes them in: a write holding a row FOR UPDATE and then the advisory lock would
  # otherwise meet an entering write holding the advisory lock and waiting for that row. A reference
  # an update sets to the value it already holds enters no set, so it takes nothing, as its foreign
  # key check takes nothing. Two orders are left that can cross: a row moving between two sets one
  # rule reads, and a create resting on a set it also enters, whose exclusive lock comes before its
  # own foreign key checks. PostgreSQL ends either by aborting one of the two writes as a deadlock
  # victim, run again by the write verbs.
  #
  # A lock is named by two 32-bit keys - one for the owner's type, one for its id - the two-key
  # space PostgreSQL keeps apart from the single-key one the schema reconciler locks in. Two names
  # hashing alike only make one write wait for another it need not have.

  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper

  @key_offset 2_147_483_648

  @key_range 4_294_967_296

  @doc """
  Returns the owner rows a pair added to the given relationship of the row with the given id
  enters a locked set of, as `{owner type, owner id}` pairs, read off the given set links.
  """
  @spec edge_owners(MapSet.t(), module, String.t(), atom, String.t()) ::
          list({module, String.t()})
  def edge_owners(links, entity_type, id, relationship_name, target_id) do
    links
    |> Enum.flat_map(fn
      {:edge, ^entity_type, ^relationship_name, :source, owner_type} -> [{owner_type, id}]
      {:edge, ^entity_type, ^relationship_name, :target, owner_type} -> [{owner_type, target_id}]
      _link -> []
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Takes the key share lock of every given owner row and every row the write references - the rows
  its foreign key checks lock - and then the shared advisory lock of every owner row, and returns
  :ok: what a write putting a row into the owners' sets holds until it commits. Takes nothing when
  there is no owner.
  """
  @spec enter!(list({module, String.t()}), list({module, String.t()})) :: :ok
  def enter!([], _referenced_rows), do: :ok

  def enter!(owners, referenced_rows) do
    owners
    |> Enum.concat(referenced_rows)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.each(&key_share!/1)

    Enum.each(owners, fn {owner_type, owner_id} ->
      lock!("pg_advisory_xact_lock_shared", owner_type, owner_id)
    end)
  end

  @doc """
  Takes the exclusive lock of the given owner row and returns :ok - what a write resting on the
  whole of a set of the row holds until it commits.
  """
  @spec hold!(module, String.t()) :: :ok
  def hold!(owner_type, owner_id) do
    lock!("pg_advisory_xact_lock", owner_type, owner_id)
  end

  @doc """
  Returns the two keys the lock of the given owner row is named by.
  """
  @spec keys(module, String.t()) :: {integer, integer}
  def keys(owner_type, owner_id) do
    {key(Atom.to_string(owner_type)), key(owner_id)}
  end

  @doc """
  Returns the owner rows a row of the given type holding the given values enters a locked set of,
  as `{owner type, owner id}` pairs, read off the given set links - for every reference field among
  the values naming a row. A creation's values are the whole row, an update's the fields it changes.
  """
  @spec row_owners(MapSet.t(), module, map) :: list({module, String.t()})
  def row_owners(links, entity_type, values) do
    links
    |> Enum.flat_map(fn
      {:reference, ^entity_type, field, owner_type} ->
        case Map.get(values, field) do
          nil -> []
          owner_id -> [{owner_type, owner_id}]
        end

      _link ->
        []
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp key(value), do: :erlang.phash2(value, @key_range) - @key_offset

  # sobelow_skip ["SQL.Query"]
  defp key_share!({entity_type, id}) do
    %{table: table} = Map.fetch!(DB.mapping(), entity_type)

    statement =
      "SELECT 1 FROM #{Mapper.quote_identifier(Mapper.data_schema())}." <>
        "#{Mapper.quote_identifier(table)} WHERE \"id\" = $1 FOR KEY SHARE"

    run!(statement, [Codec.encode(id, :uuid)])
  end

  defp lock!(function, owner_type, owner_id) do
    {type_key, id_key} = keys(owner_type, owner_id)

    run!("SELECT #{function}($1::int4, $2::int4)", [type_key, id_key])
  end

  defp run!(statement, params) do
    case Connection.query(statement, params) do
      {:ok, _result} -> :ok
      {:error, error} -> raise error
    end
  end
end
