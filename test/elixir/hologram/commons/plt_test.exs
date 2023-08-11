defmodule Hologram.Commons.PLTTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.PLT
  alias Hologram.Commons.PLT

  defp ets_table_exists?(table_ref) do
    table_ref
    |> :ets.info()
    |> is_list()
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

  # describe "delete/2" do
  #   test "key exists" do
  #     plt =
  #       @opts
  #       |> start()
  #       |> put(:my_key, :my_value)

  #     assert delete(plt, :my_key) == plt
  #     assert get(plt, :my_key) == :error
  #   end

  #   test "key doesn't exist" do
  #     plt = start(@opts)

  #     assert delete(plt, :my_key) == plt
  #     assert get(plt, :my_key) == :error
  #   end
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

  # describe "get/2" do
  #   test "key exists" do
  #     plt = start(@opts)
  #     assert get(plt, :key_1) == {:ok, :value_1}
  #   end

  #   test "key doesn't exist" do
  #     plt = start(@opts)
  #     assert get(plt, :invalid_key) == :error
  #   end
  # end

  # describe "get!/2" do
  #   test "key exists" do
  #     plt = start(@opts)
  #     assert get!(plt, :key_1) == :value_1
  #   end

  #   test "key doesn't exist" do
  #     plt = start(@opts)

  #     assert_raise KeyError, "key :invalid_key not found in the PLT", fn ->
  #       get!(plt, :invalid_key)
  #     end
  #   end
  # end

  # test "get_all/1" do
  #   plt = start(@opts)
  #   assert get_all(plt) == @items
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

  # describe "put/3" do
  #   test "first arg is %PLT{} struct" do
  #     plt =
  #       @opts
  #       |> start()
  #       |> put(:key_3, :value_3)

  #     assert get(plt, :key_3) == {:ok, :value_3}
  #   end

  #   test "first arg is PLT name" do
  #     plt = start(@opts)
  #     put(@name, :key_3, :value_3)

  #     assert get(plt, :key_3) == {:ok, :value_3}
  #   end
  # end

  # describe "start/1" do
  #   test "returns PLT struct with name and dump_path from opts" do
  #     assert %PLT{name: @name, dump_path: @dump_path} = start(@opts)
  #   end

  #   test "process name is registered" do
  #     %PLT{pid: pid} = start(@opts)
  #     assert Process.whereis(@name) == pid
  #   end

  #   test "ETS table is created if it doesn't exist yet" do
  #     start(@opts)
  #     assert ets_table_exists?(@name)
  #   end

  #   test "ETS table is not created if it already exists" do
  #     :ets.new(@name, [:public, :named_table])
  #     start(@opts)

  #     assert ets_table_exists?(@name)
  #   end

  #   test "ETS table is truncated" do
  #     :ets.new(@name, [:public, :named_table])
  #     :ets.insert(@name, {:key_3, :value_3})
  #     plt = start(@opts)

  #     assert get_all(plt) == @items
  #   end

  #   test "ETS table is populated when dump_path is given in opts and dump file exists" do
  #     plt = start(@opts)
  #     assert get_all(plt) == @items
  #   end

  #   test "ETS table is not populated when dump_path is not given in opts" do
  #     plt = start(name: @name, dump_path: nil)
  #     assert get_all(plt) == %{}
  #   end

  #   test "ETS table is not populated when dump_path is given in opts but dump file doesn't exist" do
  #     File.rm!(@dump_path)
  #     plt = start(@opts)

  #     assert get_all(plt) == %{}
  #   end

  #   test "applies custom populate table function if it is given in opts" do
  #     populate_table_fun = fn _arg ->
  #       put(@name, :custom_key_1, :custom_value_1)
  #       put(@name, :custom_key_2, :custom_value_2)
  #     end

  #     plt = start(name: @name, dump_path: @dump_path, populate_table_fun: populate_table_fun)

  #     assert get_all(plt) == %{custom_key_1: :custom_value_1, custom_key_2: :custom_value_2}
  #   end
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
