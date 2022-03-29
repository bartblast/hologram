defmodule Hologram.Commons.MemoryStoreTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Test.Fixtures.Commons.MemoryStore

  @store_content %{key_1: :value_1, key_2: :value_2}
  @table_name MemoryStore.table_name()

  defp maybe_delete_table do
    if :ets.info(@table_name) != :undefined do
      :ets.delete(@table_name)
    end
  end

  setup_all do
    file_content = Utils.serialize(@store_content)
    dump_path = MemoryStore.dump_path()

    unless File.exists?(dump_path) do
      File.write!(dump_path, file_content)
    end

    :ok
  end

  setup do
    maybe_delete_table()
    on_exit(&maybe_delete_table/0)

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
      assert MemoryStore.get(:key_1) == :value_1
    end

    test "key doesn't exist" do
      MemoryStore.run()
      expected_msg = "There is no 'key_invalid' key in test_fixture_memory_store ETS table."

      assert_raise RuntimeError, expected_msg, fn ->
        MemoryStore.get(:key_invalid)
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

    assert MemoryStore.get(:key_3) == :value_3
  end

  test "terminate/2" do
    {:ok, pid} = MemoryStore.run()
    GenServer.stop(pid)

    refute Process.whereis(MemoryStore)
    assert MemoryStore.table_name() |> :ets.info() == :undefined
  end
end
