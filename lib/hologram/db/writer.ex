defmodule Hologram.DB.Writer do
  @moduledoc false

  # The executors behind the DB verbs' struct forms: resolve a struct's claim, evaluate it
  # inside the transaction against the row as it stands, and apply the pending write through
  # EntityOperations. An update is judged by the fields it changes: each has to be covered by an
  # update rule that holds - a field-limited line covering it, or a line covering the whole row. The
  # evaluation holds the grant rows its answer rests on, and the related rows its delegations read,
  # until the transaction ends, so the authority a write was judged on is still there when it
  # commits.
  # A transaction the verb opens and PostgreSQL aborts as a deadlock victim is run again, so the
  # verb answers the way it would have a moment later. Inside a caller's transaction the error
  # propagates to it instead.
  # EntityOperations itself stays claim-blind, so the framework's own writes (a grant under an
  # acting user) reach it as they always have.

  alias Hologram.Auth
  alias Hologram.Auth.Context
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.Entity.Metadata
  alias Hologram.Job
  alias Hologram.MisuseError
  alias Hologram.Reflection

  @doc false
  @spec create(struct) :: {:ok, struct} | {:error, %{atom => list(atom | {atom, any})}}
  def create(entity) do
    stamped = stamp_job(entity)

    {:ok, result} =
      Connection.retry_on_deadlock(fn ->
        # The row being inserted is the struct in hand, so the claim is evaluated against it -
        # inside the transaction the insert runs in, which is what holds the grants the answer
        # rests on, and the related rows its delegations read, until the row lands.
        evaluate!(stamped, :create, stamped)

        stamped
        |> clean()
        |> EntityOperations.create()
      end)

    result
  end

  @doc false
  @spec delete(struct) :: :ok | {:error, %{referenced_by: module, relationship: atom}}
  def delete(entity) do
    entity_type = entity.__struct__

    {:ok, applied} =
      Connection.retry_on_deadlock(fn ->
        # No row is nothing to authorize against, and deleting an id that names none is a no-op
        # through the type-indexed verb too.
        case EntityOperations.get(entity_type, entity.id, lock: :update) do
          nil ->
            :ok

          row ->
            evaluate!(entity, :delete, row)

            EntityOperations.delete(entity_type, entity.id)
        end
      end)

    applied
  end

  # Naming the row by type and id carries no claim, so in a session this is delete/1 of a
  # struct that carries none - the verb's own operation, evaluated against the locked row.
  # With no session there is nothing to evaluate and the row is deleted raw, inside a transaction
  # of the verb's own, so a deadlock PostgreSQL resolves against it is rerun like any other.
  @doc false
  @spec delete(module, String.t()) :: :ok | {:error, %{referenced_by: module, relationship: atom}}
  def delete(entity_type, id) do
    if Context.session?() do
      delete(%{struct!(entity_type) | id: id})
    else
      {:ok, applied} =
        Connection.retry_on_deadlock(fn -> EntityOperations.delete(entity_type, id) end)

      applied
    end
  end

  @doc false
  @spec update(struct) :: :ok | {:error, %{atom => list(atom | {atom, any})}}
  def update(entity) do
    %Metadata{attribute_ops: attribute_ops, relationship_ops: relationship_ops, stamp: stamp} =
      entity.__meta__

    if attribute_ops == %{} and relationship_ops == %{} do
      raise MisuseError,
        message:
          "update takes recorded changes - put values with put_attribute, move counters with " <>
            "increment or decrement, and edges with add_relationship or delete_relationship. " <>
            "A field set directly on the struct is not recorded: writing the whole struct " <>
            "would overwrite concurrent changes to fields you didn't touch."
    end

    entity_type = entity.__struct__

    refuse_framework_attributes!(entity_type, Map.keys(attribute_ops))

    {attribute_changes, attribute_deltas} = split_attribute_ops(attribute_ops)

    fields = changed_fields(entity_type, Map.keys(attribute_ops), Map.keys(relationship_ops))

    {:ok, applied} =
      Connection.retry_on_deadlock(fn ->
        row = lock_row!(entity_type, entity.id, "update")

        evaluate_update!(entity, row, fields)

        apply_update(
          entity_type,
          entity.id,
          attribute_changes,
          attribute_deltas,
          relationship_ops,
          stamp
        )
      end)

    applied
  end

  # The type-indexed twin of update/1: no struct, so no recorded changes and no claim - the
  # changes are given outright and judged by the fields they name. With no session the row is
  # updated raw, inside a transaction of the verb's own, so a deadlock PostgreSQL resolves against
  # it is rerun like any other.
  @doc false
  @spec update(module, String.t(), map | keyword) ::
          :ok | {:error, %{atom => list(atom | {atom, any})}}
  def update(entity_type, id, changes) do
    EntityOperations.validate_update!(entity_type, changes)

    names = Enum.map(changes, fn {name, _value} -> name end)

    refuse_framework_attributes!(entity_type, names)

    if Context.session?() do
      fields = changed_fields(entity_type, names, [])

      {:ok, applied} =
        Connection.retry_on_deadlock(fn ->
          row = lock_row!(entity_type, id, "update")

          check_fields!(row, fields)

          EntityOperations.update(entity_type, id, changes)
        end)

      applied
    else
      {:ok, applied} =
        Connection.retry_on_deadlock(fn -> EntityOperations.update(entity_type, id, changes) end)

      applied
    end
  end

  @doc false
  @spec check_delete!(struct) :: :ok
  # The delete verb's own check, for the batch applier to make before the merge: a delete the merge
  # drops still answers with the row it lost to, which is an answer for whoever may delete it. The
  # write is a client's, so it is judged whether or not anyone is signed in.
  def check_delete!(row), do: evaluate_operation!(:delete, row)

  @doc false
  @spec check_update!(struct, list(atom)) :: :ok
  # The update verb's own check of the fields a client's call names - its values, its amounts and
  # its to-many edges - for the batch applier to make before the merge: whether a write is refused
  # must not turn on which of its values lose to another writer's, and a write whose every value
  # loses still answers with the columns it lost to. Judged whether or not anyone is signed in, as
  # every client write is.
  def check_update!(row, names), do: check_fields!(row, changed_fields(row.__struct__, names, []))

  defp apply_relationship_op(:add, entity_type, id, relationship_name, target_id) do
    EntityOperations.add_relationship(entity_type, id, relationship_name, target_id)
  end

  defp apply_relationship_op(:delete, entity_type, id, relationship_name, target_id) do
    EntityOperations.delete_relationship(entity_type, id, relationship_name, target_id)
  end

  # Sorted by key, so a struct carrying several edge changes applies them in one order rather
  # than the map's.
  defp apply_relationship_ops(entity_type, id, relationship_ops) do
    relationship_ops
    |> Enum.sort()
    |> Enum.each(fn {{relationship_name, target_id}, op} ->
      apply_relationship_op(op, entity_type, id, relationship_name, target_id)
    end)
  end

  # The attribute changes go first and the edges follow, all inside one transaction: a refused
  # value leaves the edges unapplied, and an edge that raises takes the values with it.
  defp apply_update(entity_type, id, attribute_changes, attribute_deltas, relationship_ops, stamp) do
    case update_attributes(entity_type, id, attribute_changes, attribute_deltas, stamp) do
      :ok -> apply_relationship_ops(entity_type, id, relationship_ops)
      {:error, violations} -> {:error, violations}
    end
  end

  # The executor returns what the row IS - the metadata the struct carried toward the write is
  # consumed here, and the stamped entity a create answers with starts over. The stamp goes
  # through: it does not describe the write, it is the revision the write is to be stored under,
  # and the insert is the only thing that can apply it.
  defp clean(entity) do
    %{entity | __meta__: %Metadata{stamp: entity.__meta__.stamp}}
  end

  # Which authority the write is on. A trust claim is the server's own and evaluates nothing. A
  # client claim is a write a browser sent, the verb's own operation evaluated whether or not a
  # session is set: a client is never the trusted tier. No claim in a session is the verb's own
  # operation on the session user's authority, with the anonymous semantics for a signed-out
  # visitor, which is what keeps every write a session makes evaluated. No claim and no session is
  # the trusted tier, and writes raw.
  defp evaluate!(%{__meta__: %Metadata{claim: :trust}}, _operation, _row), do: :ok

  defp evaluate!(%{__meta__: %Metadata{claim: :client}}, operation, row) do
    evaluate_operation!(operation, row)
  end

  defp evaluate!(_entity, operation, row) do
    if Context.session?() do
      evaluate_operation!(operation, row)
    else
      :ok
    end
  end

  # Asked with :held, so the grant rows the answer rests on, and the related rows its delegations
  # read, stay as read until the write's transaction ends - every caller of this runs inside one.
  defp evaluate_operation!(operation, row) do
    if Auth.can?(Context.actor_user_id(), operation, row, :held) do
      :ok
    else
      raise Hologram.AccessDeniedError,
        message: "not allowed to #{operation} #{inspect(row.__struct__)} #{inspect(row.id)}"
    end
  end

  # The fields an update changes, as allow lines name them: an attribute by its name, a to-one by
  # its relationship's rather than its reference field's, a to-many by its own.
  defp changed_fields(entity_type, attribute_names, relationship_op_keys) do
    reference_names =
      for {name, type, _opts} <- entity_type.__relationships__(),
          not is_list(type),
          into: %{},
          do: {String.to_existing_atom("#{name}_id"), name}

    attribute_fields = Enum.map(attribute_names, &Map.get(reference_names, &1, &1))
    relationship_fields = Enum.map(relationship_op_keys, fn {name, _target_id} -> name end)

    Enum.uniq(attribute_fields ++ relationship_fields)
  end

  # Asked with :held, as an operation is, so what the answer rests on stays as read until the write
  # commits. A refusal names every field no rule lets the acting user change.
  defp check_fields!(row, fields) do
    case Auth.uncovered_fields(Context.actor_user_id(), row, fields, :held) do
      [] ->
        :ok

      uncovered ->
        raise Hologram.AccessDeniedError,
          message:
            "not allowed to update #{inspect(row.__struct__)} #{inspect(row.id)} - no allow line that holds covers #{Enum.map_join(uncovered, ", ", &inspect/1)}"
    end
  end

  # An update is judged as any write is - by its claim, on the trusted tier not at all - but by
  # the fields it changes rather than the operation alone.
  defp evaluate_update!(%{__meta__: %Metadata{claim: :trust}}, _row, _fields), do: :ok

  defp evaluate_update!(%{__meta__: %Metadata{claim: :client}}, row, fields) do
    check_fields!(row, fields)
  end

  defp evaluate_update!(_entity, row, fields) do
    if Context.session?() do
      check_fields!(row, fields)
    else
      :ok
    end
  end

  # Read as the transaction will commit it: nothing can change the row between the claim's
  # evaluation and the write, because the row is locked from here to the commit.
  defp lock_row!(entity_type, id, verb) do
    case EntityOperations.get(entity_type, id, lock: :update) do
      nil ->
        raise MisuseError,
          message: "cannot #{verb} #{inspect(entity_type)} - no entity with id #{inspect(id)}"

      row ->
        row
    end
  end

  # The executor takes values and amounts apart: a put sets its column, an increment moves it.
  defp split_attribute_ops(attribute_ops) do
    Enum.reduce(attribute_ops, {%{}, %{}}, fn
      {name, {:put, value}}, {changes, deltas} -> {Map.put(changes, name, value), deltas}
      {name, {:increment, amount}}, {changes, deltas} -> {changes, Map.put(deltas, name, amount)}
    end)
  end

  # What a job records decides who it runs as, so no update may set it, whatever the claim: request
  # code forwarding params could otherwise choose the user a job runs as, or make it run as the
  # server. The worker records a job's progress through EntityOperations, below this check.
  defp refuse_framework_attributes!(entity_type, names) do
    framework_name =
      if Reflection.job?(entity_type) do
        Enum.find(Job.framework_attribute_names(), &(&1 in names))
      end

    if framework_name do
      raise MisuseError,
        message:
          "#{inspect(framework_name)} of #{inspect(entity_type)} is set by the framework - an update can't change it"
    end

    :ok
  end

  # Only code the server trusts runs a job as the server: code outside a session, or a trust claim
  # with no user to record. A client's write never does, and a job with no mark runs as an anonymous
  # session, so anything unforeseen fails closed.
  defp run_as_server?(%{__meta__: %Metadata{claim: :client}}), do: false

  defp run_as_server?(%{__meta__: %Metadata{claim: :trust}}) do
    Context.actor_entity_id() == nil
  end

  defp run_as_server?(_entity), do: not Context.session?()

  # A job records who enqueued it, and that is a fact of the write rather than of the struct: the
  # ambient actor as a user entity's id at the moment it is written, nobody on the trusted tier or
  # for an actor no user entity can be, and whether it runs as the server. Stamped before the claim
  # is evaluated, so a policy naming the field judges the value the row will
  # hold - and stamped over whatever the struct carries, the way the executor stamps the
  # timestamps.
  #
  # It is due from now, by this node's clock: a browser's own clock can be set as far back as it
  # likes, and the queue is ordered by this time, so a job it wrote must not be able to jump it.
  defp stamp_job(entity) do
    if Reflection.job?(entity.__struct__) do
      %{
        entity
        | actor_id: Context.actor_entity_id(),
          run_as_server: run_as_server?(entity),
          scheduled_at: DateTime.utc_now()
      }
    else
      entity
    end
  end

  defp update_attributes(_entity_type, _id, attribute_changes, attribute_deltas, _stamp)
       when map_size(attribute_changes) == 0 and map_size(attribute_deltas) == 0,
       do: :ok

  defp update_attributes(entity_type, id, attribute_changes, attribute_deltas, stamp) do
    # An absent stamp is left absent rather than passed as nil: the option's presence is what
    # says a revision was authored elsewhere, and a nil under the key would reach the statement.
    # Deltas travel the same way: present only when the struct recorded some.
    stamp_opts = if stamp, do: [stamp: stamp], else: []

    opts =
      if attribute_deltas == %{}, do: stamp_opts, else: [{:deltas, attribute_deltas} | stamp_opts]

    EntityOperations.update(entity_type, id, attribute_changes, opts)
  end
end
