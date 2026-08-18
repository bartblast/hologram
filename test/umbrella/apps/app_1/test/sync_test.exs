defmodule App1.SyncTest do
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

  describe "the runtime bundle" do
    # The other half of the same rule, at the other end of the wire: a build with no data layer
    # does not ADVERTISE sync, so a client of it never greets. The server refuses one anyway, for
    # the stale bundle that asks after a deploy - these are not alternatives.
    test "carries no sync constants, so no client of it asks to sync" do
      pattern =
        Path.join([Application.app_dir(:app_1, "priv"), "static", "hologram", "runtime-*.js"])

      assert [bundle_path] = Path.wildcard(pattern)

      bundle = File.read!(bundle_path)

      # The positive artifact beside the negative one, so a bundle that failed to build cannot
      # pass this by holding nothing at all.
      assert String.contains?(bundle, "Hologram.config")

      # The hash rather than the word: the reader of these constants is in every bundle and names
      # them whatever the build declares, so only the VALUE says whether this one was told.
      refute String.contains?(bundle, Model.hash())

      # And what IS assigned is null, explicitly - not an empty object, which is truthy, so a
      # client finding one would greet with undefined fields rather than staying quiet. One
      # unambiguous value beats probing for a missing global.
      assert String.contains?(bundle, "Hologram.sync=null")
    end
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
