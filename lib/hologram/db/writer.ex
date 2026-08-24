defmodule Hologram.DB.Writer do
  @moduledoc false

  # The executors behind the DB verbs' struct forms: resolve a struct's claim, evaluate it
  # inside the transaction against the row as it stands, and apply the pending write through
  # EntityOperations. EntityOperations itself stays claim-blind, so the framework's own writes
  # (a grant under an acting user) reach it as they always have.

  alias Hologram.Auth
  alias Hologram.Auth.Context
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

  # The executor returns what the row IS - the metadata the struct carried toward the write is
  # consumed here, and the stamped entity a create answers with starts over.
  defp clean(entity) do
    %{entity | __meta__: %Metadata{}}
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
end
