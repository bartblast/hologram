defmodule Hologram.Runtime.PageDigestRegistryTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Runtime.PageDigestRegistry
  import Mox

  alias Hologram.Commons.ETS
  alias Hologram.Commons.PLT
  alias Hologram.Commons.Reflection
  alias Hologram.Runtime.PageDigestRegistry

  defmodule Stub do
    @behaviour PageDigestRegistry

    def dump_path, do: "#{Reflection.tmp_path()}/#{__MODULE__}.plt"

    def ets_table_name, do: __MODULE__
  end

  setup :set_mox_global

  setup do
    File.rm(Stub.dump_path())

    PLT.start()
    |> PLT.put(:module_1, :aaa)
    |> PLT.put(:module_2, :bbb)
    |> PLT.put(:module_3, :ccc)
    |> PLT.dump(Stub.dump_path())

    stub_with(PageDigestRegistry.Mock, Stub)

    :ok
  end

  test "init/1" do
    assert {:ok, nil} = init(nil)

    assert ets_table_exists?(Stub.ets_table_name())
    assert ETS.get_all(Stub.ets_table_name()) == %{module_1: :aaa, module_2: :bbb, module_3: :ccc}
  end

  describe "lookup/2" do
    setup do
      init(nil)
      :ok
    end

    test "module entry exists" do
      assert lookup(:module_2) == :bbb
    end

    test "module entry doesn't exist" do
      assert_raise KeyError, "key :module_4 not found in the PLT", fn ->
        lookup(:module_4)
      end
    end
  end

  test "start_link/1" do
    assert {:ok, pid} = start_link([])
    assert is_pid(pid)
    assert ets_table_exists?(Stub.ets_table_name())
  end
end
