defmodule Hologram.Sync.HandshakeTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Sync.Handshake

  alias Hologram.Entity.Model
  alias Hologram.Policy
  alias Hologram.Sync.Frame

  # The rules this build enforces, stood in the cache so a test can name them: hashing the suite's
  # whole model reads derived field definitions no test of the handshake puts.
  @policy_hash "0123456789abcdef0123456789abcdef"

  setup do
    on_exit(&Policy.reset_model_facts_cache/0)

    :persistent_term.put({Policy, :hash}, @policy_hash)

    :ok
  end

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
      assert check(greeting()) == {:sync, MyApp.BoardPage, nil, @policy_hash, false}
    end

    test "takes the page the client names at face value" do
      assert check(greeting(%{page: MyApp.SomeOtherPage})) ==
               {:sync, MyApp.SomeOtherPage, nil, @policy_hash, false}
    end

    test "passes a returning client's place through without reading it" do
      assert check(greeting(%{cursor: "g8uxAAAAZQ"})) ==
               {:sync, MyApp.BoardPage, "g8uxAAAAZQ", @policy_hash, false}
    end

    # A place this build cannot read is still the log's business, not the bundle's - answering it
    # here would put the same decision in two places and let them disagree.
    test "passes a place it cannot make sense of through just the same" do
      assert check(greeting(%{cursor: "not a cursor"})) ==
               {:sync, MyApp.BoardPage, "not a cursor", @policy_hash, false}
    end

    test "serves a client arriving for the first time, which names no place" do
      first_visit = Map.delete(greeting(), :cursor)

      assert check(first_visit) == {:sync, MyApp.BoardPage, nil, @policy_hash, false}
    end

    # A deploy that changed only policies leaves the model as it was, so the client is served - and
    # told the rules it is behind on beside its rows.
    test "serves a client built with other rules, saying its rules are behind" do
      assert check(greeting(%{policy_hash: "fedcba9876543210fedcba9876543210"})) ==
               {:sync, MyApp.BoardPage, nil, @policy_hash, true}
    end

    test "serves a client built with this build's rules as current" do
      assert check(greeting(%{policy_hash: @policy_hash})) ==
               {:sync, MyApp.BoardPage, nil, @policy_hash, false}
    end

    # A bundle that checks no permissions is shipped empty rules, which no deploy can leave behind.
    test "serves a client naming no rules as current" do
      assert check(greeting(%{policy_hash: nil})) ==
               {:sync, MyApp.BoardPage, nil, @policy_hash, false}
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

    # Neither the model nor its hash can be read under a hold, so the answer waits for the release.
    test "holds off a client arriving while the data model is held" do
      on_exit(&Model.release/0)

      arriving = greeting()
      Model.hold()

      assert check(arriving) == :held
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
      assert {:sync, _page, _cursor, _policy_hash, _stale_rules?} = check(greeting())
    end
  end
end
