defmodule Hologram.Commons.MemoryStoreTest do
  use Hologram.Test.BasicCase, async: false

  alias Hologram.Commons.SerializationUtils
  alias Hologram.Test.Fixtures.Commons.MemoryStore.Module1, as: StoreFixture
  alias Hologram.Test.Fixtures.Commons.MemoryStore.Module2

  @dump_path StoreFixture.dump_path()
  @store_items %{key_1: :value_1, key_2: :value_2}

  defp dump_store_items(store_items) do
    binary = SerializationUtils.serialize(store_items)
    File.write!(@dump_path, binary)
  end

  defp wait_for_test_cleanup do
    if StoreFixture.running?() || StoreFixture.table_exists?() do
      :timer.sleep(1)
      wait_for_test_cleanup()
    end
  end

  setup do
    wait_for_test_cleanup()
    dump_store_items(@store_items)

    :ok
  end

  describe "run/0" do
    test "process name is registered" do
      {:ok, pid} = StoreFixture.run()
      assert Process.whereis(StoreFixture) == pid
    end

    test "ETS table is created if it doesn't exist yet" do
      StoreFixture.run()
      assert StoreFixture |> :ets.info() |> is_list()
    end

    test "ETS table is not created if it already exists" do
      :ets.new(StoreFixture, [:public, :named_table])
      StoreFixture.run()

      assert StoreFixture |> :ets.info() |> is_list()
    end

    test "ETS table is truncated" do
      :ets.new(StoreFixture, [:public, :named_table])
      :ets.insert(StoreFixture, {:key_3, :value_3})
      StoreFixture.run()

      assert StoreFixture.get_all() == @store_items
    end

    test "ETS table is populated" do
      StoreFixture.run()
      assert StoreFixture.get_all() == @store_items
    end
  end

  describe "get/1, default implementation" do
    test "key exists" do
      StoreFixture.run()
      assert StoreFixture.get(:key_1) == {:ok, :value_1}
    end

    test "key doesn't exist" do
      StoreFixture.run()
      assert StoreFixture.get(:key_invalid) == :error
    end
  end

  test "get/1, overriding implementation" do
    Module2.run()
    assert Module2.get(:key_1) == {:ok, "overriden_value_for_key_1"}
  end

  test "get_all/0" do
    StoreFixture.run()
    assert StoreFixture.get_all() == @store_items
  end

  test "put/1" do
    StoreFixture.run()

    items = [
      {:key_3, :value_3},
      {:key_4, :value_4}
    ]

    StoreFixture.put(items)

    assert StoreFixture.get(:key_3) == {:ok, :value_3}
    assert StoreFixture.get(:key_4) == {:ok, :value_4}
  end

  test "put/2" do
    StoreFixture.run()
    StoreFixture.put(:key_3, :value_3)

    assert StoreFixture.get(:key_3) == {:ok, :value_3}
  end

  describe "running?/0" do
    test "is running" do
      StoreFixture.run()
      assert StoreFixture.running?()
    end

    test "is not running" do
      refute StoreFixture.running?()
    end
  end

  describe "table_exists?/0" do
    test "exists" do
      :ets.new(StoreFixture, [:public, :named_table])
      assert StoreFixture.table_exists?()
    end

    test "doesn't exist" do
      refute StoreFixture.table_exists?()
    end
  end
end
