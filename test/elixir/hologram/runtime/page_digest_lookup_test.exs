defmodule Hologram.Runtime.PageDigestLookupTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Runtime.PageDigestLookup

  alias Hologram.Commons.PLT
  alias Hologram.Commons.Reflection

  @dump_path "#{Reflection.tmp_path()}/#{__MODULE__}/test.plt"
  @table_name random_atom()

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
    assert {:ok, %PLT{table_name: @table_name} = plt} =
             init(table_name: @table_name, dump_path: @dump_path)

    assert PLT.get_all(plt) == %{module_1: :aaa, module_2: :bbb, module_3: :ccc}
  end
end
