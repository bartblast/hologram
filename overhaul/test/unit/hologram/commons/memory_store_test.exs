defmodule Hologram.Commons.MemoryStore.Module1Test do
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

  describe "has?/1" do
    test "true" do
      Module1.run()
      Module1.put(:key_3, 123)
      assert Module1.has?(:key_3)
    end

    test "false" do
      Module1.run()
      refute Module1.has?(:key_3)
    end
  end

  test "lock/1" do
    Module1.run()
    Module1.lock(:key_3)

    assert Module1.get(:key_3) == {:ok, :lock}
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

  test "reload/1" do
    Module1.run()

    changed_store_content = %{changed_key: :changed_value}
    dump_store_content(changed_store_content)
    Module1.reload()

    assert Module1.get_all() == changed_store_content
  end

  test "stop/0 (and terminate/2 implicitely)" do
    Module1.run()
    Module1.stop()

    refute Module1.running?()
    assert Module1.table_name() |> :ets.info() == :undefined
  end
end
