defmodule App1.SyncHandshakeTest do
  use ExUnit.Case, async: true

  alias Hologram.Entity.Model
  alias Hologram.Sync.Frame
  alias Hologram.Sync.Handshake

  # This umbrella declares no entity types, so it has no database - the application tree gates the
  # whole data layer on exactly that. Every page here is therefore unsyncable, and a client that
  # greets anyway has to be told no.
  #
  # Answering otherwise is not a tidiness problem: the greeting is checked AFTER the stream has
  # sent its 200, so reaching for a pool that was never started killed a connected request, and
  # the client counted the open as a success and retried at its base delay for as long as CI ran.
  defp greeting(overrides \\ %{}) do
    Map.merge(
      %{
        cursor: nil,
        model_hash: Model.hash(),
        page: App3.Page,
        protocol_version: Frame.protocol_version()
      },
      overrides
    )
  end

  describe "check/1" do
    test "refuses to sync a build that declares no entity types" do
      assert Hologram.Reflection.list_entities() == []
      assert Handshake.check(greeting()) == :no_sync
    end

    # Ahead of the bundle checks on purpose: with no data layer there is nothing to serve whatever
    # the client's bundle says, and a reload notice would send it away to come back to the same no.
    test "says so rather than sending the client away to reload" do
      stale_bundle = greeting(%{model_hash: "a3f9c2"})
      stale_protocol = greeting(%{protocol_version: 99})

      assert Handshake.check(stale_bundle) == :no_sync
      assert Handshake.check(stale_protocol) == :no_sync
    end
  end
end
