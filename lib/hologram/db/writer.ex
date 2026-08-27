defmodule Hologram.DB.Writer do
  @moduledoc false

  # The executors behind the DB verbs' struct forms: resolve a struct's claim, evaluate it
  # inside the transaction against the row as it stands, and apply the pending write through
  # EntityOperations. EntityOperations itself stays claim-blind, so the framework's own writes
  # (a grant under an acting user) reach it as they always have.

  alias Hologram.Auth
  alias Hologram.Auth.Context
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.Entity.Metadata

  @doc false
  @spec create(struct) :: {:ok, struct} | {:error, %{atom => list(atom | {atom, any})}}
  def create(entity) do
    # The row being inserted is the struct in hand - nothing a transaction could change - so the
    # claim is evaluated against it before the write's own transaction opens.
    evaluate!(entity, :create, entity)

    entity
    |> clean()
    |> EntityOperations.create()
  end

  @doc false
  @spec delete(struct) :: :ok | {:error, %{referenced_by: module, relationship: atom}}
  def delete(entity) do
    entity_type = entity.__struct__

    {:ok, applied} =
      Connection.transaction(fn ->
        # No row is nothing to authorize against, and deleting an id that names none is a no-op
        # through the type-indexed verb too.
        case EntityOperations.get(entity_type, entity.id, lock: true) do
          nil ->
            :ok

          row ->
            evaluate!(entity, :delete, row)

            EntityOperations.delete(entity_type, entity.id)
        end
      end)

    applied
  end

  # Naming the row by type and id carries no claim, so under an actor this is delete/1 of a
  # struct that carries none - the verb's own operation, evaluated against the locked row.
  # Without an actor there is nothing to evaluate and the row is deleted raw, as before.
  @doc false
  @spec delete(module, String.t()) :: :ok | {:error, %{referenced_by: module, relationship: atom}}
  def delete(entity_type, id) do
    if Context.actor_user_id() do
      delete(%{struct!(entity_type) | id: id})
    else
      EntityOperations.delete(entity_type, id)
    end
  end

  @doc false
  @spec update(struct) :: :ok | {:error, %{atom => list(atom | {atom, any})}}
  def update(entity) do
    %Metadata{
      attribute_changes: attribute_changes,
      attribute_deltas: attribute_deltas,
      relationship_ops: relationship_ops,
      stamp: stamp
    } = entity.__meta__

    if attribute_changes == %{} and attribute_deltas == %{} and relationship_ops == %{} do
      raise ArgumentError,
        message:
          "update takes recorded changes - put values with put_attribute, move counters with " <>
            "increment or decrement, and edges with add_relationship or delete_relationship. " <>
            "A field set directly on the struct is not recorded: writing the whole struct " <>
            "would overwrite concurrent changes to fields you didn't touch."
    end

    entity_type = entity.__struct__

    {:ok, applied} =
      Connection.transaction(fn ->
        row = lock_row!(entity_type, entity.id, "update")

        evaluate!(entity, :update, row)

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
  # changes are given outright and the operation is the verb's own.
  @doc false
  @spec update(module, String.t(), map | keyword) ::
          :ok | {:error, %{atom => list(atom | {atom, any})}}
  def update(entity_type, id, changes) do
    if Context.actor_user_id() do
      {:ok, applied} =
        Connection.transaction(fn ->
          row = lock_row!(entity_type, id, "update")

          evaluate_operation!(:update, row)

          EntityOperations.update(entity_type, id, changes)
        end)

      applied
    else
      EntityOperations.update(entity_type, id, changes)
    end
  end

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

  # Which authority the write is on, and for which operation. A trust claim is the server's own
  # and evaluates nothing. An authorize claim names an operation and is evaluated whether or not
  # an actor is set - without one the evaluator's anonymous semantics apply, which is what a seed
  # claiming a user's authority gets. No claim under an actor is the verb's own operation on the
  # acting user's authority, which is what keeps every write under an actor evaluated. No claim
  # and no actor is the trusted tier, and writes raw.
  defp evaluate!(%{__meta__: %Metadata{claim: :trust}}, _default_operation, _row), do: :ok

  defp evaluate!(%{__meta__: %Metadata{claim: {:authorize, operation}}}, _default_operation, row) do
    evaluate_operation!(operation, row)
  end

  defp evaluate!(_entity, default_operation, row) do
    if Context.actor_user_id() do
      evaluate_operation!(default_operation, row)
    else
      :ok
    end
  end

  defp evaluate_operation!(operation, row) do
    if Auth.can?(Context.actor_user_id(), operation, row) do
      :ok
    else
      raise Hologram.AccessDeniedError,
        message: "not allowed to #{operation} #{inspect(row.__struct__)} #{inspect(row.id)}"
    end
  end

  # Read as the transaction will commit it: nothing can change the row between the claim's
  # evaluation and the write, because the row is locked from here to the commit.
  defp lock_row!(entity_type, id, verb) do
    case EntityOperations.get(entity_type, id, lock: true) do
      nil ->
        raise ArgumentError,
          message: "cannot #{verb} #{inspect(entity_type)} - no entity with id #{inspect(id)}"

      row ->
        row
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
