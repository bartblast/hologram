defmodule Hologram.Commons.PLTTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.PLT
  alias Hologram.Commons.PLT

  defp ets_table_exists?(table_ref) do
    table_ref
    |> :ets.info()
    |> is_list()
  end

  describe "delete/2" do
    test "key exists" do
      plt =
        start()
        |> put(:my_key, :my_value)

      assert delete(plt, :my_key) == plt
      assert get(plt, :my_key) == :error
    end

    test "key doesn't exist" do
      plt = start()

      assert delete(plt, :my_key) == plt
      assert get(plt, :my_key) == :error
    end
  end

  describe "get/2" do
    test "key exists" do
      plt =
        start()
        |> put(:my_key, :my_value)

      assert get(plt, :my_key) == {:ok, :my_value}
    end

    test "key doesn't exist" do
      plt = start()
      assert get(plt, :invalid_key) == :error
    end
  end

  describe "get!/2" do
    test "key exists" do
      plt =
        start()
        |> put(:my_key, :my_value)

      assert get!(plt, :my_key) == :my_value
    end

    test "key doesn't exist" do
      plt = start()

      assert_raise KeyError, "key :invalid_key not found in the PLT", fn ->
        get!(plt, :invalid_key)
      end
    end
  end

  describe "put/3" do
    test "first arg is a PLT struct" do
      result =
        start()
        |> put(:my_key, :my_value)
        |> get(:my_key)

      assert result == {:ok, :my_value}
    end

    test "first arg is an ETS table ref" do
      %{table_ref: table_ref} = plt = start()
      put(table_ref, :my_key, :my_value)

      assert get(plt, :my_key) == {:ok, :my_value}
    end
  end

  test "start/0" do
    assert %PLT{pid: pid, table_ref: table_ref} = start()

    assert is_pid(pid)
    assert is_reference(table_ref)

    assert ets_table_exists?(table_ref)
  end

  # alias Hologram.Commons.SerializationUtils
  # alias Hologram.Compiler.Reflection

  # @dump_path Reflection.tmp_path() <> "/plt_#{__MODULE__}.bin"
  # @items %{key_1: :value_1, key_2: :value_2}
  # @name :"plt_#{__MODULE__}"
  # @opts name: @name, dump_path: @dump_path

  # defp dump_items do
  #   binary = SerializationUtils.serialize(@items)
  #   File.write!(@dump_path, binary)
  # end

  # setup do
  #   wait_for_plt_cleanup(@name)
  #   dump_items()

  #   :ok
  # end

  # test "dump/1" do
  #   @opts
  #   |> start()
  #   |> put(:dump_test, 123)
  #   |> dump()

  #   items =
  #     @dump_path
  #     |> File.read!()
  #     |> SerializationUtils.deserialize()

  #   assert items.dump_test == 123
  # end

  # test "put/2" do
  #   plt = start(@opts)

  #   items = [
  #     {:key_3, :value_3},
  #     {:key_4, :value_4}
  #   ]

  #   put(@name, items)

  #   assert get(plt, :key_3) == {:ok, :value_3}
  #   assert get(plt, :key_4) == {:ok, :value_4}
  # end

  # describe "table_exists?/1" do
  #   test "exists" do
  #     :ets.new(@name, [:public, :named_table])
  #     assert table_exists?(@name)
  #   end

  #   test "doesn't exist" do
  #     refute table_exists?(@name)
  #   end
  # end
end
