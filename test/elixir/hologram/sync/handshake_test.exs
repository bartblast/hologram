defmodule Hologram.Sync.HandshakeTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Sync.Handshake
  import Hologram.Test.Stubs

  alias Hologram.Entity.Model
  alias Hologram.Policy
  alias Hologram.Sync.Frame
  alias Hologram.Sync.Lens
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3

  use_module_stub :query_cache

  # The rules this build enforces, stood in the cache so a test can name them: hashing the suite's
  # whole model reads derived field definitions no test of the handshake puts.
  @policy_hash "0123456789abcdef0123456789abcdef"

  setup do
    on_exit(&Policy.reset_model_facts_cache/0)
    on_exit(&Lens.reset_cache/0)

    :persistent_term.put({Policy, :hash}, @policy_hash)

    setup_query_cache(QueryCacheStub, false)

    :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
      permission_checking?: false,
      synced_types: [Module2, Module3]
    })

    :ok
  end

  @old_version "20260101000000"
  @current_version "20260201000000"

  # A history as the migration table and the release's migrations give it, stood in the lens's
  # cache so the handshake reads it without a database: the tab's point creates MyApp.OldTask with
  # a `title`, and the file after it renames the type to Module2 and `title` to `c`, or does what
  # the test gives instead.
  defp stand_history(later_ops \\ nil) do
    later_ops =
      later_ops ||
        [
          %{op: :rename_entity, from: MyApp.OldTask, to: Module2},
          %{op: :rename_attribute, entity: Module2, from: :title, to: :c}
        ]

    migrations = [
      %{
        ops: [
          %{op: :create_entity, entity: MyApp.OldTask},
          %{op: :add_attribute, entity: MyApp.OldTask, name: :title, type: :string, opts: []}
        ],
        version: @old_version
      },
      %{ops: later_ops, version: @current_version}
    ]

    # Folding to the running model, as a consistent release's files do.
    history = %{
      Lens.history(%{@old_version => "0ld", @current_version => Model.hash()}, migrations)
      | model_hash: Model.hash()
    }

    :persistent_term.put({Lens, :history, Model.hash()}, {:ok, history})
  end

  defp old_greeting(overrides \\ %{}) do
    greeting(Map.merge(%{model_hash: "0ld", synced_types: ["MyApp.OldTask"]}, overrides))
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
      assert check(greeting()) ==
               {:sync, MyApp.BoardPage, nil, @policy_hash, false, %{lens: nil, types: nil}}
    end

    test "takes the page the client names at face value" do
      assert check(greeting(%{page: MyApp.SomeOtherPage})) ==
               {:sync, MyApp.SomeOtherPage, nil, @policy_hash, false, %{lens: nil, types: nil}}
    end

    test "passes a returning client's place through without reading it" do
      assert check(greeting(%{cursor: "g8uxAAAAZQ"})) ==
               {:sync, MyApp.BoardPage, "g8uxAAAAZQ", @policy_hash, false,
                %{lens: nil, types: nil}}
    end

    # A place this build cannot read is still the log's business, not the bundle's - answering it
    # here would put the same decision in two places and let them disagree.
    test "passes a place it cannot make sense of through just the same" do
      assert check(greeting(%{cursor: "not a cursor"})) ==
               {:sync, MyApp.BoardPage, "not a cursor", @policy_hash, false,
                %{lens: nil, types: nil}}
    end

    test "serves a client arriving for the first time, which names no place" do
      first_visit = Map.delete(greeting(), :cursor)

      assert check(first_visit) ==
               {:sync, MyApp.BoardPage, nil, @policy_hash, false, %{lens: nil, types: nil}}
    end

    # A deploy that changed only policies leaves the model as it was, so the client is served - and
    # told the rules it is behind on beside its rows.
    test "serves a client built with other rules, saying its rules are behind" do
      assert check(greeting(%{policy_hash: "fedcba9876543210fedcba9876543210"})) ==
               {:sync, MyApp.BoardPage, nil, @policy_hash, true, %{lens: nil, types: nil}}
    end

    test "serves a client built with this build's rules as current" do
      assert check(greeting(%{policy_hash: @policy_hash})) ==
               {:sync, MyApp.BoardPage, nil, @policy_hash, false, %{lens: nil, types: nil}}
    end

    # Every bundle names the rules it answers by, so a greeting naming none is a test client's.
    test "serves a client naming no rules as current" do
      assert check(greeting(%{policy_hash: nil})) ==
               {:sync, MyApp.BoardPage, nil, @policy_hash, false, %{lens: nil, types: nil}}
    end

    test "reloads a client speaking another protocol version" do
      assert check(greeting(%{protocol_version: Frame.protocol_version() + 1})) ==
               {:reload, :protocol_version}
    end

    test "reloads a client built against a model the history doesn't know" do
      stand_history()

      assert check(greeting(%{model_hash: "a3f9c2", synced_types: []})) == {:reload, :model_hash}
    end

    test "serves a client built against an earlier point of the history through a lens" do
      stand_history()

      assert {:sync, MyApp.BoardPage, nil, @policy_hash, false, %{lens: lens, types: [Module2]}} =
               check(old_greeting(%{cursor: nil}))

      assert Lens.old_type(lens, Module2) == MyApp.OldTask
      assert Lens.old_attribute(lens, Module2, :c) == :title
    end

    # The current rules name what the current model calls things, and would be judged over rows in
    # the client's shape.
    test "never says an old client's rules are behind" do
      stand_history()

      assert {:sync, _page, _cursor, _policy_hash, false, _serving} =
               check(old_greeting(%{policy_hash: "fedcba9876543210fedcba9876543210"}))
    end

    test "passes an old client's place through" do
      stand_history()

      assert {:sync, _page, "g8uxAAAAZQ", _policy_hash, _stale_rules?, _serving} =
               check(old_greeting(%{cursor: "g8uxAAAAZQ"}))
    end

    test "reloads an old client whose greeting says nothing of the types its bundle syncs" do
      stand_history()

      assert check(Map.delete(old_greeting(), :synced_types)) == {:reload, :model_hash}
    end

    test "serves an old client whose bundle syncs no type nothing" do
      stand_history()

      assert {:sync, _page, _cursor, _policy_hash, false, %{types: []}} =
               check(old_greeting(%{synced_types: []}))
    end

    # No rows of a type only an older build's code read are coming, since this build syncs none.
    test "reloads an old client naming a type this build doesn't sync" do
      stand_history()

      assert check(old_greeting(%{synced_types: ["MyApp.OldTask", "MyApp.Gone"]})) ==
               {:reload, :model_hash}
    end

    test "reloads an old client across a change renaming can't give back" do
      stand_history([%{op: :delete_attribute, entity: MyApp.OldTask, name: :title}])

      assert check(old_greeting()) == {:reload, :model_hash}
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
      assert {:sync, _page, _cursor, _policy_hash, _stale_rules?, _serving} = check(greeting())
    end
  end
end
