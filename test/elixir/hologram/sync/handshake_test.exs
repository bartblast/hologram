defmodule Hologram.Sync.HandshakeTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Sync.Handshake

  alias Hologram.Entity.Model
  alias Hologram.Sync.Frame

  defp greeting(overrides \\ %{}) do
    Map.merge(
      %{
        cursor: nil,
        model_hash: Model.hash(),
        page: MyApp.BoardPage,
        protocol_version: Frame.protocol_version()
      },
      overrides
    )
  end

  describe "check/1" do
    test "serves a client speaking this build's protocol and model" do
      assert check(greeting()) == {:sync, MyApp.BoardPage, nil}
    end

    test "takes the page the client names at face value" do
      assert check(greeting(%{page: MyApp.SomeOtherPage})) == {:sync, MyApp.SomeOtherPage, nil}
    end

    test "passes a returning client's place through without reading it" do
      assert check(greeting(%{cursor: "g8uxAAAAZQ"})) == {:sync, MyApp.BoardPage, "g8uxAAAAZQ"}
    end

    # A place this build cannot read is still the log's business, not the bundle's - answering it
    # here would put the same decision in two places and let them disagree.
    test "passes a place it cannot make sense of through just the same" do
      assert check(greeting(%{cursor: "not a cursor"})) ==
               {:sync, MyApp.BoardPage, "not a cursor"}
    end

    test "serves a client arriving for the first time, which names no place" do
      first_visit = Map.delete(greeting(), :cursor)

      assert check(first_visit) == {:sync, MyApp.BoardPage, nil}
    end

    test "reloads a client speaking another protocol version" do
      assert check(greeting(%{protocol_version: Frame.protocol_version() + 1})) ==
               {:reload, :protocol_version}
    end

    test "reloads a client built against another model" do
      assert check(greeting(%{model_hash: "a3f9c2"})) == {:reload, :model_hash}
    end

    # The protocol decides how the rest of the greeting is even spelled, so a version this build
    # does not speak is answered before anything else in it is believed.
    test "reloads on the protocol version before looking at the model" do
      disagreeing = greeting(%{model_hash: "a3f9c2", protocol_version: 99})

      assert check(disagreeing) == {:reload, :protocol_version}
    end

    test "leaves a client that said nothing about sync alone" do
      assert check(%{}) == :no_sync
    end

    test "leaves a client that said only part of it alone" do
      assert check(%{page: MyApp.BoardPage}) == :no_sync
    end

    # The other side of this - a build with NO entity types answering :no_sync - cannot be shown
    # here, because this suite's own model has twenty of them and nothing stubs the reflection.
    # It is asserted in the umbrella app, which declares none, and which is where the crash this
    # gate exists to prevent actually happened.
    test "serves a client of a build that has a data model" do
      refute Hologram.Reflection.list_entities() == []
      assert {:sync, _page, _cursor} = check(greeting())
    end
  end
end
