defmodule Hologram.ControllerMutationTest do
  # async: false - the subscription registry and the realtime processes are node-global, and the
  # instance cross-check reads the registry.
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.Controller

  alias Hologram.Compiler.Encoder
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.Entity
  alias Hologram.Entity.Model
  alias Hologram.Realtime.SubscriptionRegistry
  alias Hologram.Realtime.Tombstone
  alias Hologram.Runtime.CSRFProtection
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module19
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Policy.Module2, as: PolicyModule2

  @unmasked_csrf_token CSRFProtection.generate_unmasked_token()
  @masked_csrf_token CSRFProtection.get_masked_token(@unmasked_csrf_token)

  @instance_id "test-instance-id"

  @anonymous_session %{
    CSRFProtection.session_key() => @unmasked_csrf_token,
    hologram_session_id: "test-session-id"
  }

  setup do
    wait_for_process_cleanup(SubscriptionRegistry)
    start_supervised!(SubscriptionRegistry)

    wait_for_process_cleanup(Hologram.PubSub)
    start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

    wait_for_process_cleanup(Tombstone)
    start_supervised!({Tombstone, boot_sync_timeout_ms: 0})

    :ok
  end

  # An update claiming the one operation the fixtures grant without a role grant - refused with
  # :not_found while the row it names is absent, and landing once it exists.
  defp archive_write(id) do
    %{
      "op" => "update",
      "type" => inspect(PolicyModule1),
      "id" => id,
      "data" => %{"priority" => 9},
      "claim" => ["authorize", "archive"],
      "stamp" => System.os_time(:millisecond) * 1024
    }
  end

  defp create_user(email) do
    Module14
    |> Entity.new(email: email)
    |> DB.create!()
  end

  defp envelope(writes, opts \\ []) do
    %{
      "instance_id" => @instance_id,
      "replica_id" => Keyword.get(opts, :replica_id, Entity.generate_id()),
      "model_hash" => Keyword.get(opts, :model_hash, Model.hash()),
      "seq" => 1,
      "writes" => writes
    }
  end

  # Scoped to the batch by its own mutation_ref rather than reading the whole table: the outbox is
  # shared, and what this file asks about is the effects of ONE batch.
  defp outbox_actor_ids(replica_id) do
    statement = """
    SELECT "actor_id"
    FROM "hologram_system"."outbox"
    WHERE "mutation_ref"->>'replica_id' = $1
    ORDER BY "seq"
    """

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement, [replica_id])

    Enum.map(rows, fn [actor_id] -> Codec.decode(actor_id, :uuid) end)
  end

  defp post_batch(raw, session \\ @anonymous_session, opts \\ []) do
    :post
    |> Plug.Test.conn("/hologram/mutation", "")
    |> Plug.Test.init_test_session(session)
    |> Map.put(:body_params, raw)
    |> put_csrf_header(Keyword.get(opts, :csrf_token, @masked_csrf_token))
    |> handle_mutation_request()
  end

  defp publish_write(id, opts \\ []) do
    %{
      "op" => "create",
      "type" => inspect(PolicyModule2),
      "id" => id,
      "data" => %{"public" => true},
      "claim" => ["authorize", "publish"],
      "stamp" => Keyword.get(opts, :stamp, System.os_time(:millisecond) * 1024)
    }
  end

  defp put_csrf_header(conn, nil), do: conn

  defp put_csrf_header(conn, token), do: Plug.Conn.put_req_header(conn, "x-csrf-token", token)

  defp session_of(user_id), do: Map.put(@anonymous_session, :hologram_user_id, user_id)

  describe "handle_mutation_request/1" do
    test "applies a batch and answers confirmed" do
      id = Entity.generate_id()

      conn = post_batch(envelope([publish_write(id)]))

      assert conn.halted == true
      assert conn.state == :sent
      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == %{"status" => "confirmed", "dropped" => %{}}

      assert EntityOperations.get(PolicyModule2, id) != nil
    end

    test "applies the batch under the session's user" do
      user = create_user("publisher@example.com")
      replica_id = Entity.generate_id()

      raw = envelope([publish_write(Entity.generate_id())], replica_id: replica_id)

      conn = post_batch(raw, session_of(user.id))

      assert conn.status == 200

      assert outbox_actor_ids(replica_id) == [user.id]
    end

    test "answers a refused batch with the write and the reason" do
      write = %{
        "op" => "create",
        "type" => inspect(Module19),
        "id" => Entity.generate_id(),
        "data" => %{"code" => "c"},
        "claim" => ["authorize", "read"],
        "stamp" => System.os_time(:millisecond) * 1024
      }

      conn = post_batch(envelope([write]))

      assert conn.status == 200

      assert Jason.decode!(conn.resp_body) == %{
               "status" => "rejected",
               "write" => 0,
               "reason" => Encoder.encode_client_term!(%{slug: [:required]})
             }
    end

    test "answers a refused batch posted again with what its first arrival got" do
      user = create_user("resender@example.com")
      replica_id = Entity.generate_id()
      id = Entity.generate_id()
      raw = envelope([archive_write(id)], replica_id: replica_id)

      first = post_batch(raw, session_of(user.id))

      # The world changes between the two posts - a second evaluation would find the row and land
      # the update - so an answer that still refuses is one the record replayed.
      PolicyModule1
      |> Entity.new(id: id, author_id: user.id, priority: 5)
      |> DB.create!()

      second = post_batch(raw, session_of(user.id))

      assert first.status == 200
      assert second.status == 200

      # The bytes, not the decoded map: a replay that re-encoded the reason could spell it
      # differently and still decode equal.
      assert second.resp_body == first.resp_body

      assert Jason.decode!(first.resp_body)["status"] == "rejected"
      assert EntityOperations.get(PolicyModule1, id).priority == 5
    end

    test "answers a batch built against another model with no write" do
      raw = envelope([publish_write(Entity.generate_id())], model_hash: "other")

      conn = post_batch(raw)

      assert conn.status == 200

      assert Jason.decode!(conn.resp_body) == %{
               "status" => "rejected",
               "write" => nil,
               "reason" => Encoder.encode_client_term!(:stale_build)
             }
    end

    test "answers a malformed batch as a bad request" do
      conn = post_batch(%{envelope([]) | "writes" => "nope"})

      assert conn.halted == true
      assert conn.state == :sent
      assert conn.status == 400
      assert conn.resp_body == "writes must be a list"
    end

    test "refuses a batch with no CSRF token" do
      conn =
        post_batch(envelope([publish_write(Entity.generate_id())]), @anonymous_session,
          csrf_token: nil
        )

      assert conn.halted == true
      assert conn.status == 403
      assert conn.resp_body == "Forbidden"
    end

    test "refuses a batch whose CSRF token does not match the session" do
      other_token = CSRFProtection.get_masked_token(CSRFProtection.generate_unmasked_token())

      conn =
        post_batch(envelope([publish_write(Entity.generate_id())]), @anonymous_session,
          csrf_token: other_token
        )

      assert conn.halted == true
      assert conn.status == 403
      assert conn.resp_body == "Forbidden"
    end

    test "refuses a batch from an instance the session does not own" do
      :ok = SubscriptionRegistry.register_connection(@instance_id, self())
      :ok = SubscriptionRegistry.update_identity(@instance_id, "other-session-id", nil)

      conn = post_batch(envelope([publish_write(Entity.generate_id())]))

      assert conn.halted == true
      assert conn.status == 403
      assert conn.resp_body == "Forbidden"
    end
  end
end
