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

  # Reads the registry as fast as it can until asked what it saw, so a reload that empties the
  # table even briefly is caught rather than stepped over.
  defp watch_lookups(report_to, page_module, seen) do
    receive do
      {:report, ^report_to} -> send(report_to, {:answers, seen})
    after
      0 -> watch_lookups(report_to, page_module, [lookup(page_module) | seen])
    end
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

  describe "all/0" do
    test "returns the windows of every page, not only those of one" do
      init(nil)

      assert Enum.sort(all()) == ["w_7f3a", "w_c412", "w_gone"]
    end

    test "returns a window two pages both download once" do
      dump(%{
        MyApp.BoardPage => ["w_7f3a", "w_c412"],
        MyApp.SettingsPage => ["w_c412"]
      })

      init(nil)

      assert Enum.sort(all()) == ["w_7f3a", "w_c412"]
    end

    test "returns nothing for a build with no pages" do
      dump(%{})

      init(nil)

      assert all() == []
    end
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

    # The window this guards is the one between clearing and filling. A session that looked in
    # there would be handed no windows for a page that has them - and a session with nothing
    # outstanding announces at once that the client's store is complete, so the client would be
    # told it holds everything while holding nothing.
    test "never answers with nothing for a page it holds, however often it is reloaded" do
      init(nil)

      test_pid = self()
      reader = spawn_link(fn -> watch_lookups(test_pid, MyApp.BoardPage, []) end)

      Enum.each(1..200, fn _round -> reload() end)

      send(reader, {:report, self()})
      assert_receive {:answers, answers}

      assert Enum.uniq(answers) == [["w_7f3a", "w_c412"]]
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
