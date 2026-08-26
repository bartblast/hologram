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

  defp create_user(email) do
    Module14
    |> Entity.new(email: email)
    |> DB.create!()
  end

  defp envelope(writes, opts \\ []) do
    %{
      "instance_id" => @instance_id,
      "client_id" => Keyword.get(opts, :client_id, Entity.generate_id()),
      "model_hash" => Keyword.get(opts, :model_hash, Model.hash()),
      "seq" => 1,
      "writes" => writes
    }
  end

  defp outbox_actor_ids do
    {:ok, %Postgrex.Result{rows: rows}} =
      Connection.query(~s|SELECT "actor_id" FROM "hologram_system"."outbox" ORDER BY "seq"|)

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

      conn = post_batch(envelope([publish_write(Entity.generate_id())]), session_of(user.id))

      assert conn.status == 200

      # The user's own creation comes first and has no actor - this test process is the trusted
      # tier. The batch's effect is the one that carries the session's user.
      assert outbox_actor_ids() == [nil, user.id]
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
