defmodule Hologram.Sync.WindowStoreTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Sync.WindowStore

  alias Hologram.Sync.WindowStore
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3

  @window_id "w_7f3a"
  @other_window_id "w_c412"

  setup do
    wait_for_process_cleanup(WindowStore)
    start_supervised!(WindowStore)

    :ok
  end

  defp term(entity_type) do
    %{entity: entity_type, filter: [], include: %{}, order_by: []}
  end

  describe "all/0" do
    test "returns nothing while no window is held" do
      assert all() == []
    end

    test "returns every held window with the term it was registered under" do
      register(@window_id, term(Module2))
      register(@other_window_id, term(Module3))

      assert Enum.sort(all()) ==
               Enum.sort([{@window_id, term(Module2)}, {@other_window_id, term(Module3)}])
    end

    test "leaves out a window nobody holds any more" do
      register(@window_id, term(Module2))
      register(@other_window_id, term(Module3))
      unregister(@window_id)

      assert all() == [{@other_window_id, term(Module3)}]
    end
  end

  describe "fetch/1" do
    test "returns the term registered under the given key" do
      register(@window_id, term(Module2))

      assert fetch(@window_id) == term(Module2)
    end

    test "returns nil when nothing holds the given key" do
      assert fetch(@window_id) == nil
    end
  end

  describe "register/2" do
    test "counts the first holder" do
      assert register(@window_id, term(Module2)) == 1
    end

    test "counts each holder after the first" do
      register(@window_id, term(Module2))

      assert register(@window_id, term(Module2)) == 2
      assert register(@window_id, term(Module2)) == 3
    end

    test "keeps the term the first holder registered" do
      register(@window_id, term(Module2))
      register(@window_id, term(Module3))

      assert fetch(@window_id) == term(Module2)
    end

    test "counts holders of one key without counting them for another" do
      register(@window_id, term(Module2))
      register(@window_id, term(Module2))

      assert register(@other_window_id, term(Module2)) == 1
    end
  end

  describe "unregister/1" do
    test "returns how many holders are left" do
      register(@window_id, term(Module2))
      register(@window_id, term(Module2))

      assert unregister(@window_id) == 1
    end

    test "forgets the window once the last holder lets go" do
      register(@window_id, term(Module2))

      assert unregister(@window_id) == 0
      assert fetch(@window_id) == nil
    end

    test "answers zero for a key nobody holds" do
      assert unregister(@window_id) == 0
    end

    test "answers zero for a key that was already forgotten" do
      register(@window_id, term(Module2))
      unregister(@window_id)

      assert unregister(@window_id) == 0
    end
  end
end
