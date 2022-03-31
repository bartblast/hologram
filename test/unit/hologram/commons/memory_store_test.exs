defmodule Hologram.Commons.MemoryStoreTest do
  use Hologram.Test.UnitCase, async: false
  alias Hologram.Test.Fixtures.Commons.MemoryStore

  @dump_path MemoryStore.dump_path()
  @store_content %{key_1: :value_1, key_2: :value_2}
  @table_name MemoryStore.table_name()

  defp dump_store_content(store_content) do
    bin_content = Utils.serialize(store_content)
    File.write!(@dump_path, bin_content)
  end

  defp running? do
    pid = Process.whereis(MemoryStore)
    if pid, do: Process.alive?(pid), else: false
  end

  defp wait_for_test_cleanup do
    if running?() || :ets.info(@table_name) != :undefined do
      :timer.sleep(1)
      wait_for_test_cleanup()
    end
  end

  setup do
    wait_for_test_cleanup()
    dump_store_content(@store_content)

    :ok
  end

  describe "run/0" do
    test "process name is registered" do
      {:ok, pid} = MemoryStore.run()
      assert Process.whereis(MemoryStore) == pid
    end

    test "ETS table is created if it doesn't exist yet" do
      MemoryStore.run()
      assert :ets.info(@table_name) |> is_list()
    end

    test "ETS table is not created if it already exists" do
      :ets.new(@table_name, [:public, :named_table])
      MemoryStore.run()

      assert :ets.info(@table_name) |> is_list()
    end

    test "ETS table is truncated" do
      :ets.new(@table_name, [:public, :named_table])
      :ets.insert(@table_name, {:key_3, :value_3})
      MemoryStore.run()

      assert MemoryStore.get_all() == @store_content
    end

    test "ETS table is populated" do
      MemoryStore.run()
      assert MemoryStore.get_all() == @store_content
    end
  end

  describe "get/1" do
    test "key exists" do
      MemoryStore.run()
      assert MemoryStore.get(:key_1) == {:ok, :value_1}
    end

    test "key doesn't exist" do
      MemoryStore.run()
      assert MemoryStore.get(:key_invalid) == :error
    end
  end

  describe "get!/1" do
    test "key exists" do
      MemoryStore.run()
      assert MemoryStore.get!(:key_1) == :value_1
    end

    test "key doesn't exist" do
      MemoryStore.run()

      assert_raise KeyError, "key :key_invalid not found", fn ->
        MemoryStore.get!(:key_invalid)
      end
    end
  end

  test "get_all/0" do
    MemoryStore.run()
    assert MemoryStore.get_all() == @store_content
  end

  test "put/2" do
    MemoryStore.run()
    MemoryStore.put(:key_3, :value_3)

    assert MemoryStore.get(:key_3) == {:ok, :value_3}
  end

  test "reload/0" do
    MemoryStore.run()

    changed_store_content = %{changed_key: :changed_value}
    dump_store_content(changed_store_content)
    MemoryStore.reload()

    assert MemoryStore.get_all() == changed_store_content
  end

  test "stop/0 (and terminate/2 implicitely)" do
    MemoryStore.run()
    MemoryStore.stop()

    refute running?()
    assert MemoryStore.table_name() |> :ets.info() == :undefined
  end
end
