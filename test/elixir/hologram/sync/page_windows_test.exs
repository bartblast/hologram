defmodule Hologram.Sync.PageWindowsTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Sync.PageWindows
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Commons.ETS
  alias Hologram.Commons.PLT
  alias Hologram.Reflection
  alias Hologram.Sync.PageWindows

  use_module_stub :sync_page_windows

  setup :set_mox_global

  defp dump(items) do
    dump_path = SyncPageWindowsStub.dump_path()

    File.rm(dump_path)

    dump_path
    |> Path.dirname()
    |> File.mkdir_p!()

    items
    |> Enum.reduce(PLT.start(), fn {key, value}, plt -> PLT.put(plt, key, value) end)
    |> PLT.dump(dump_path)

    :ok
  end

  setup do
    setup_sync_page_windows(SyncPageWindowsStub, false)

    dump(%{
      MyApp.BoardPage => ["w_7f3a", "w_c412"],
      MyApp.QuietPage => [],
      MyApp.RemovedPage => ["w_gone"]
    })

    :ok
  end

  describe "init/1" do
    test "reads the windows the build worked out" do
      assert init(nil) == {:ok, nil}

      assert ETS.get_all(SyncPageWindowsStub.ets_table_name()) == %{
               MyApp.BoardPage => ["w_7f3a", "w_c412"],
               MyApp.QuietPage => [],
               MyApp.RemovedPage => ["w_gone"]
             }
    end
  end

  describe "lookup/1" do
    setup do
      init(nil)

      :ok
    end

    test "returns the windows of a page that downloads some" do
      assert lookup(MyApp.BoardPage) == ["w_7f3a", "w_c412"]
    end

    test "returns nothing for a page that downloads none" do
      assert lookup(MyApp.QuietPage) == []
    end

    test "returns nothing for a module that is not a page of this build" do
      assert lookup(MyApp.NeverCompiled) == []
    end
  end

  describe "reload/0" do
    test "picks up windows the build worked out since" do
      init(nil)

      dump(%{MyApp.BoardPage => ["w_new"]})

      reload()

      assert lookup(MyApp.BoardPage) == ["w_new"]
    end

    test "forgets a page the build no longer has" do
      init(nil)

      assert lookup(MyApp.RemovedPage) == ["w_gone"]

      dump(%{MyApp.BoardPage => ["w_7f3a", "w_c412"]})

      reload()

      assert lookup(MyApp.RemovedPage) == []
    end
  end

  describe "dump_path/0" do
    test "reads from the build directory" do
      assert PageWindows.dump_path() ==
               Path.join([Reflection.build_dir(), Reflection.page_windows_plt_dump_file_name()])
    end
  end
end
