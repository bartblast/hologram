defmodule Hologram.Runtime.PageDigestLookupTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Runtime.PageDigestLookup

  alias Hologram.Commons.PLT
  alias Hologram.Commons.Reflection

  @dump_path "#{Reflection.tmp_path()}/#{__MODULE__}/test.plt"
  @table_name random_atom()
  @opts [table_name: @table_name, dump_path: @dump_path]

  setup do
    File.rm(@dump_path)

    PLT.start()
    |> PLT.put(:module_1, :aaa)
    |> PLT.put(:module_2, :bbb)
    |> PLT.put(:module_3, :ccc)
    |> PLT.dump(@dump_path)

    :ok
  end

  test "init/1" do
    assert {:ok, %PLT{table_name: @table_name} = plt} = init(@opts)

    assert ets_table_exists?(@table_name)
    assert PLT.get_all(plt) == %{module_1: :aaa, module_2: :bbb, module_3: :ccc}
  end

  describe "lookup/2" do
    setup do
      init(@opts)
      :ok
    end

    test "module entry exists" do
      assert lookup(@table_name, :module_2) == :bbb
    end

    test "module entry doesn't exist" do
      assert_raise KeyError, "key :module_4 not found in the PLT", fn ->
        lookup(@table_name, :module_4)
      end
    end
  end

  test "start_link/1" do
    assert {:ok, pid} = start_link(@opts)
    assert is_pid(pid)
    assert ets_table_exists?(@table_name)
  end
end
