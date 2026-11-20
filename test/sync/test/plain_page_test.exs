defmodule HologramSyncTests.PlainPageTest do
  use HologramSyncTests.TestCase, async: false

  test "the plain page answers" do
    {:ok, {{_version, status, _reason}, _headers, _body}} =
      :httpc.request(:get, {~c"#{base_url()}/plain", []}, [], [])

    assert status == 200
  end

  test "a client syncing from the plain page is told it holds everything" do
    client =
      SyncClient.connect(base_url(), cookie_path: "/plain", page: "HologramSyncTests.PlainPage")

    on_exit(fn -> SyncClient.close(client) end)

    assert await_scope(client, "all") == "all"
  end

  # Each client holds a stream open, and none may wait behind another's.
  test "several clients sync at once" do
    clients =
      for _index <- 1..5 do
        client =
          SyncClient.connect(base_url(),
            cookie_path: "/plain",
            page: "HologramSyncTests.PlainPage"
          )

        on_exit(fn -> SyncClient.close(client) end)

        client
      end

    assert Enum.map(clients, &await_scope(&1, "all")) == List.duplicate("all", 5)
  end

  # The scope of each completeness marker until one names the given scope - a type's marker comes
  # before the one for everything.
  defp await_scope(client, scope) do
    {frame, next_client} = SyncClient.await_frame(client, "synced")

    case Jason.decode!(frame["data"]) do
      %{"scope" => ^scope} -> scope
      _other_scope -> await_scope(next_client, scope)
    end
  end
end
