defmodule Hologram.Commons.MemoryStore.Module1Test do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Test.Fixtures.Commons.MemoryStore.Module1
  alias Hologram.Test.Fixtures.Commons.MemoryStore.Module2

  @dump_path Module1.dump_path()
  @store_content %{key_1: :value_1, key_2: :value_2}
  @table_name Module1.table_name()

  defp dump_store_content(store_content) do
    bin_content = Utils.serialize(store_content)
    File.write!(@dump_path, bin_content)
  end

  defp wait_for_test_cleanup do
    if Module1.running?() || :ets.info(@table_name) != :undefined do
      :timer.sleep(1)
      wait_for_test_cleanup()
    end
  end

  setup do
    wait_for_test_cleanup()
    dump_store_content(@store_content)

    :ok
  end

  describe "run/1" do
    test "process name is registered" do
      {:ok, pid} = Module1.run()
      assert Process.whereis(Module1) == pid
    end

    test "ETS table is created if it doesn't exist yet" do
      Module1.run()
      assert :ets.info(@table_name) |> is_list()
    end

    test "ETS table is not created if it already exists" do
      :ets.new(@table_name, [:public, :named_table])
      Module1.run()

      assert :ets.info(@table_name) |> is_list()
    end

    test "ETS table is truncated" do
      :ets.new(@table_name, [:public, :named_table])
      :ets.insert(@table_name, {:key_3, :value_3})
      Module1.run()

      assert Module1.get_all() == @store_content
    end

    test "ETS table is populated" do
      Module1.run()
      assert Module1.get_all() == @store_content
    end
  end

  describe "get/1, default implementation" do
    test "key exists" do
      Module1.run()
      assert Module1.get(:key_1) == {:ok, :value_1}
    end

    test "key doesn't exist" do
      Module1.run()
      assert Module1.get(:key_invalid) == :error
    end
  end

  test "get/1, overriding implementation" do
    Module2.run()
    assert Module2.get(:key_1) == {:ok, "result_for_key_1"}
  end

  describe "get!/1" do
    test "key exists" do
      Module1.run()
      assert Module1.get!(:key_1) == :value_1
    end

    test "key doesn't exist" do
      Module1.run()

      assert_raise KeyError, "key :key_invalid not found", fn ->
        Module1.get!(:key_invalid)
      end
    end
  end

  test "get_all/0" do
    Module1.run()
    assert Module1.get_all() == @store_content
  end

  describe "maybe_stop/0" do
    test "is running" do
      Module1.run()
      Module1.maybe_stop()

      refute Module1.running?()
    end

    test "is not running" do
      Module1.maybe_stop()
      refute Module1.running?()
    end
  end

  test "put/1" do
    Module1.run()

    items = [
      {:key_3, :value_3},
      {:key_4, :value_4}
    ]

    Module1.put(items)

    assert Module1.get(:key_3) == {:ok, :value_3}
    assert Module1.get(:key_4) == {:ok, :value_4}
  end

  test "put/2" do
    Module1.run()
    Module1.put(:key_3, :value_3)

    assert Module1.get(:key_3) == {:ok, :value_3}
  end

  test "reload/1" do
    Module1.run()

    changed_store_content = %{changed_key: :changed_value}
    dump_store_content(changed_store_content)
    Module1.reload()

    assert Module1.get_all() == changed_store_content
  end

  describe "running?/0" do
    test "is running" do
      Module1.run()
      assert Module1.running?()
    end

    test "is not running" do
      refute Module1.running?()
    end
  end

  test "stop/0 (and terminate/2 implicitely)" do
    Module1.run()
    Module1.stop()

    refute Module1.running?()
    assert Module1.table_name() |> :ets.info() == :undefined
  end
end
