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
    setup_page_digest_registry_dump(Stub)
    stub_with(PageDigestRegistry.Mock, Stub)

    :ok
  end

  test "init/1" do
    assert {:ok, nil} = init(nil)

    assert ets_table_exists?(Stub.ets_table_name())

    assert ETS.get_all(Stub.ets_table_name()) == %{
             module_a: :module_a_digest,
             module_b: :module_b_digest,
             module_c: :module_c_digest
           }
  end

  describe "lookup/2" do
    setup do
      init(nil)
      :ok
    end

    test "module entry exists" do
      assert lookup(:module_b) == :module_b_digest
    end

    test "module entry doesn't exist" do
      assert_raise KeyError, "key :module_d not found in the PLT", fn ->
        lookup(:module_d)
      end
    end
  end

  test "start_link/1" do
    assert {:ok, pid} = start_link([])
    assert is_pid(pid)
    assert ets_table_exists?(Stub.ets_table_name())
  end
end
