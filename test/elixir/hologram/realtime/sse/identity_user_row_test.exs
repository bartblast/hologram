defmodule Hologram.Realtime.SSE.IdentityUserRowTest do
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.Realtime.SSE
  import Hologram.Test.Stubs

  alias Hologram.DB
  alias Hologram.Realtime.SubscriptionRegistry
  alias Hologram.Test.Fixtures.Entity.Module14

  use_module_stub :query_cache

  setup do
    wait_for_process_cleanup(Hologram.PubSub)
    start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

    wait_for_process_cleanup(SubscriptionRegistry)
    start_supervised!(SubscriptionRegistry)

    setup_query_cache(QueryCacheStub, false)

    :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
      permission_checking?: false,
      synced_types: []
    })

    :ok
  end

  defp identity_payload(conn) do
    "event: sync_identity\nid: " <> rest = conn.resp_body
    [_match, data] = Regex.run(~r/\A\d+\ndata: (.*)\n\n\z/, rest)

    Jason.decode!(data)
  end

  defp prepared_conn do
    :get
    |> Plug.Test.conn("/")
    |> prepare()
    |> Plug.Conn.fetch_query_params()
  end

  # The tab holds the new user's row before its stream fills it, as a page's first render does.
  test "tells the client the new user's row with who its session is now" do
    user =
      %{email: "sse_identity_1@example.com", password_hash: "hash_7qLr"}
      |> Module14.new()
      |> DB.create!()

    send(self(), {:identity_changed, "session-1", user.id, "1.tag"})

    {:cont, updated_conn, _session_id, _user_id, nil} =
      process_message(prepared_conn(), "session-1", nil)

    assert %{
             "user_row" => %{"put_entity" => %{"Hologram.Test.Fixtures.Entity.Module14" => [row]}}
           } =
             identity_payload(updated_conn)

    assert row["id"] == user.id
    assert row["email"] == "sse_identity_1@example.com"
    refute Map.has_key?(row, "password_hash")
  end

  test "names no row when the session's user has none" do
    send(self(), {:identity_changed, "session-1", Hologram.Entity.generate_id(), "1.tag"})

    {:cont, updated_conn, _session_id, _user_id, nil} =
      process_message(prepared_conn(), "session-1", nil)

    payload = identity_payload(updated_conn)

    refute Map.has_key?(payload, "user_row")
  end
end
