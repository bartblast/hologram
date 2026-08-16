defmodule Hologram.Sync.FanoutTest do
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.Sync.Fanout
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.DB
  alias Hologram.Entity
  alias Hologram.Query
  alias Hologram.Sync.Evaluator
  alias Hologram.Sync.Evaluators
  alias Hologram.Sync.ResultStore
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1

  use_module_stub :query_cache

  setup :set_mox_global

  @board_window "w_board"
  @other_window "w_other"

  setup do
    setup_query_cache(QueryCacheStub, false)

    :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
      entries: %{},
      prop_params: %{},
      windows: %{
        @board_window => Query.normalize(Module2),
        @other_window => Query.normalize(PolicyModule1)
      }
    })

    wait_for_process_cleanup(ResultStore)
    start_supervised!(ResultStore)

    wait_for_process_cleanup(Evaluator.registry())
    start_supervised!({Registry, keys: :unique, name: Evaluator.registry()})

    wait_for_process_cleanup(Evaluators)
    start_supervised!(Evaluators)

    :ok
  end

  defp hold(window_id) do
    {:ok, evaluator, _version} = Evaluators.subscribe(window_id, self())

    DBConnection.Ownership.ownership_allow(DB.pool_name(), self(), evaluator, [])

    evaluator
  end

  defp transactions(entity_type) do
    [{200, [%{op: :patch_entity, type: entity_type, entity_id: Entity.generate_id(), data: %{}}]}]
  end

  describe "route/1" do
    test "hands the batch to the evaluator of a window the writes could have changed" do
      hold(@board_window)

      route(transactions(Module2))

      assert_receive {:round, @board_window, 1, _transactions}
    end

    test "leaves alone a window the writes could not have changed" do
      hold(@other_window)

      route(transactions(Module3))

      refute_receive {:round, _window_id, _version, _transactions}, 100
    end

    test "hands the batch to every affected window" do
      hold(@board_window)
      hold(@other_window)

      route(transactions(Module2) ++ transactions(PolicyModule1))

      assert_receive {:round, @board_window, 1, _board_transactions}
      assert_receive {:round, @other_window, 1, _other_transactions}
    end

    test "hands over the whole batch rather than the part concerning the window" do
      hold(@board_window)

      batch = transactions(Module2) ++ transactions(Module3)

      route(batch)

      assert_receive {:round, @board_window, 1, handed_over}
      assert handed_over == batch
    end

    test "tells nothing when no window is held" do
      assert route(transactions(Module2)) == :ok
    end

    test "tells a window whose policy reads the grants that changed" do
      hold(@other_window)

      route(transactions(Hologram.Auth.RoleGrant))

      assert_receive {:round, @other_window, 1, _transactions}
    end
  end
end
