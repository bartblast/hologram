defmodule Hologram.Runtime.PageDigestRegistryTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Runtime.PageDigestRegistry

  alias Hologram.Commons.PLT
  alias Hologram.Commons.Reflection

  @dump_path "#{Reflection.tmp_path()}/#{__MODULE__}/test.plt"
  @store_key random_atom()
  @opts [store_key: @store_key, dump_path: @dump_path]

  setup do
    File.rm(@dump_path)

    PLT.start()
    |> PLT.put(:module_1, :aaa)
    |> PLT.put(:module_2, :bbb)
    |> PLT.put(:module_3, :ccc)
    |> PLT.dump(@dump_path)

    :ok
  end

  describe "handle_call/3" do
    test "get_plt" do
      {:ok, pid} = start_link(@opts)
      assert %PLT{} = GenServer.call(pid, :get_plt)
    end
  end

  test "init/1" do
    assert {:ok, %PLT{table_name: @store_key} = plt} = init(@opts)

    assert ets_table_exists?(@store_key)
    assert PLT.get_all(plt) == %{module_1: :aaa, module_2: :bbb, module_3: :ccc}
  end

  describe "lookup/2" do
    setup do
      init(@opts)
      :ok
    end

    test "module entry exists" do
      assert lookup(@store_key, :module_2) == :bbb
    end

    test "module entry doesn't exist" do
      assert_raise KeyError, "key :module_4 not found in the PLT", fn ->
        lookup(@store_key, :module_4)
      end
    end
  end

  test "start_link/1" do
    assert {:ok, pid} = start_link(@opts)
    assert is_pid(pid)
    assert ets_table_exists?(@store_key)
  end
end
