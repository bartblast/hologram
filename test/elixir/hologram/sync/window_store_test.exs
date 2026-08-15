defmodule Hologram.Sync.WindowStoreTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Sync.WindowStore

  alias Hologram.Sync.WindowStore
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3

  @key {"q_7f3a", %{project_id: "pA"}}
  @other_key {"q_7f3a", %{project_id: "pB"}}

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
      register(@key, term(Module2))
      register(@other_key, term(Module3))

      assert Enum.sort(all()) == Enum.sort([{@key, term(Module2)}, {@other_key, term(Module3)}])
    end

    test "leaves out a window nobody holds any more" do
      register(@key, term(Module2))
      register(@other_key, term(Module3))
      unregister(@key)

      assert all() == [{@other_key, term(Module3)}]
    end
  end

  describe "fetch/1" do
    test "returns the term registered under the given key" do
      register(@key, term(Module2))

      assert fetch(@key) == term(Module2)
    end

    test "returns nil when nothing holds the given key" do
      assert fetch(@key) == nil
    end
  end

  describe "register/2" do
    test "counts the first holder" do
      assert register(@key, term(Module2)) == 1
    end

    test "counts each holder after the first" do
      register(@key, term(Module2))

      assert register(@key, term(Module2)) == 2
      assert register(@key, term(Module2)) == 3
    end

    test "keeps the term the first holder registered" do
      register(@key, term(Module2))
      register(@key, term(Module3))

      assert fetch(@key) == term(Module2)
    end

    test "counts holders of one key without counting them for another" do
      register(@key, term(Module2))
      register(@key, term(Module2))

      assert register(@other_key, term(Module2)) == 1
    end
  end

  describe "unregister/1" do
    test "returns how many holders are left" do
      register(@key, term(Module2))
      register(@key, term(Module2))

      assert unregister(@key) == 1
    end

    test "forgets the window once the last holder lets go" do
      register(@key, term(Module2))

      assert unregister(@key) == 0
      assert fetch(@key) == nil
    end

    test "answers zero for a key nobody holds" do
      assert unregister(@key) == 0
    end

    test "answers zero for a key that was already forgotten" do
      register(@key, term(Module2))
      unregister(@key)

      assert unregister(@key) == 0
    end
  end
end
