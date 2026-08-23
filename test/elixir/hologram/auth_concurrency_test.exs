defmodule Hologram.AuthConcurrencyTest do
  # Not sandboxed and not async: the guard being tested spans two statements, so the racing
  # revokes must run on separate connections against committed rows. Sync tests run after every
  # async one has finished, so the committed rows are never visible to a sandboxed test.
  use Hologram.Test.BasicCase, async: false

  import Hologram.Auth

  alias Hologram.Auth.Context
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Entity
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Policy.Module1

  defp count_managing_grants(resource_id) do
    select_sql =
      ~s|SELECT count(*) FROM "hologram_data"."hologram_role_grant" | <>
        ~s|WHERE "resource_id" = $1|

    {:ok, %{rows: [[count]]}} = Connection.query(select_sql, [Codec.encode(resource_id, :uuid)])

    count
  end

  defp create_owner(email) do
    Module14
    |> Entity.new(email: email)
    |> DB.create!()
  end

  # The revokers are started, then released together: without the barrier each one tends to
  # finish before the next is scheduled, and the window the guard has to close never opens.
  defp delete_rows(owners, resource) do
    encoded_resource_id = Codec.encode(resource.id, :uuid)
    encoded_owner_ids = Enum.map(owners, &Codec.encode(&1.id, :uuid))

    deletions = [
      {~s|DELETE FROM "hologram_data"."hologram_role_grant" WHERE "resource_id" = $1|,
       [encoded_resource_id]},
      {~s|DELETE FROM "hologram_data"."#{Mapper.table_name(Module1)}" WHERE "id" = $1|,
       [encoded_resource_id]},
      {~s|DELETE FROM "hologram_data"."#{Mapper.table_name(Module14)}" WHERE "id" = ANY($1)|,
       [encoded_owner_ids]}
    ]

    Enum.each(deletions, fn {statement, params} ->
      {:ok, _result} = Connection.query(statement, params)
    end)
  end

  defp revoke_concurrently(owners, resource) do
    parent = self()

    revokers =
      Enum.map(owners, fn owner ->
        spawn(fn ->
          send(parent, {:ready, self()})
          receive do: (:go -> :ok)

          outcome =
            try do
              Context.with_actor(owner.id, fn -> revoke_role(owner, resource, :owner) end)
            rescue
              error -> {:rejected, error.__struct__}
            end

          send(parent, {:revoked, outcome})
        end)
      end)

    Enum.each(revokers, fn revoker -> receive do: ({:ready, ^revoker} -> :ok) end)
    Enum.each(revokers, &send(&1, :go))

    Enum.map(revokers, fn _revoker -> receive do: ({:revoked, outcome} -> outcome) end)
  end

  test "concurrent revocations never strip a resource of its last managing role" do
    owners = Enum.map(1..2, &create_owner("concurrency_#{&1}@example.com"))

    resource =
      Module1
      |> Entity.new()
      |> DB.create!()

    Enum.each(owners, &grant_role(&1, resource, :owner))

    # The rows are committed, so they outlive the test and would be counted by the sandboxed
    # tests that run alongside - grants first, since they reference the users.
    on_exit(fn -> delete_rows(owners, resource) end)

    outcomes = revoke_concurrently(owners, resource)

    assert :ok in outcomes
    assert {:rejected, Hologram.AccessDeniedError} in outcomes
    assert count_managing_grants(resource.id) == 1
  end
end
