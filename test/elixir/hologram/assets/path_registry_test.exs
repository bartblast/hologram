defmodule Hologram.Assets.PathRegistryTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Assets.PathRegistry
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.Commons.ETS

  use_module_stub :asset_path_registry

  setup :set_mox_global

  setup do
    setup_asset_path_registry(AssetPathRegistryStub, false)
  end

  # Reads the registry as fast as it can until asked what it saw, so a reload that empties the
  # table even briefly is caught rather than stepped over.
  defp watch_lookups(report_to, static_path, seen) do
    receive do
      {:report, ^report_to} -> send(report_to, {:answers, seen})
    after
      0 -> watch_lookups(report_to, static_path, [lookup(static_path) | seen])
    end
  end

  test "get_mapping/0", %{mapping: mapping} do
    AssetPathRegistry.start_link([])
    assert get_mapping() == mapping
  end

  describe "handle_call/3" do
    test "get_mapping", %{mapping: mapping} do
      AssetPathRegistry.start_link([])
      process_name = AssetPathRegistryStub.process_name()

      assert GenServer.call(process_name, :get_mapping) == mapping
    end
  end

  test "init/1", %{mapping: mapping} do
    ets_table_name = AssetPathRegistryStub.ets_table_name()

    assert init(nil) == {:ok, nil}
    assert ets_table_exists?(ets_table_name)
    assert ETS.get_all(ets_table_name) == mapping
  end

  describe "lookup/2" do
    setup do
      AssetPathRegistry.start_link([])
      :ok
    end

    test "asset exists, has digest suffix" do
      assert lookup("test_dir_1/test_dir_2/test_file_1.css") ==
               {:ok, "/test_dir_1/test_dir_2/test_file_1-11111111111111111111111111111111.css"}
    end

    test "asset exists, doesn't have digest suffix" do
      assert lookup("test_dir_3/test_file_10.css") ==
               {:ok, "/test_dir_3/test_file_10.css"}
    end

    test "asset doesn't exist" do
      assert lookup("invalid_file.css") == :error
    end
  end

  test "register/2" do
    AssetPathRegistry.start_link([])
    AssetPathRegistry.register("my_static_path", "/my_asset_path")

    assert lookup("my_static_path") == {:ok, "/my_asset_path"}
  end

  test "reload/0", %{mapping: mapping} do
    AssetPathRegistry.start_link([])

    ets_table_name = AssetPathRegistryStub.ets_table_name()
    ETS.put(ets_table_name, :dummy_key, :dummy_value)

    reload()

    assert ETS.get_all(ets_table_name) == mapping
  end

  # A reload that empties the table first leaves every asset unresolvable for as long as the walk
  # of the static dir takes, which is the slowest thing here - so a page rendered in that window
  # would be served links to assets the registry says do not exist.
  test "reload/0 never answers with nothing for an asset it holds", %{mapping: mapping} do
    AssetPathRegistry.start_link([])

    [{static_path, asset_path} | _rest] = Map.to_list(mapping)

    test_pid = self()
    reader = spawn_link(fn -> watch_lookups(test_pid, static_path, []) end)

    Enum.each(1..50, fn _round -> reload() end)

    send(reader, {:report, self()})
    assert_receive {:answers, answers}

    assert Enum.uniq(answers) == [{:ok, asset_path}]
  end

  test "start_link/1" do
    assert {:ok, pid} = AssetPathRegistry.start_link([])
    assert is_pid(pid)
    assert process_name_registered?(AssetPathRegistryStub.process_name())
    assert ets_table_exists?(AssetPathRegistryStub.ets_table_name())
  end
end
