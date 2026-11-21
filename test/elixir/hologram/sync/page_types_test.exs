defmodule Hologram.Sync.PageTypesTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Sync.PageTypes
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Commons.ETS
  alias Hologram.Commons.PLT
  alias Hologram.Reflection
  alias Hologram.Sync.PageTypes

  use_module_stub :sync_page_types

  setup :set_mox_global

  defp dump(items) do
    dump_path = SyncPageTypesStub.dump_path()

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
  # table even briefly is caught rather than stepped over. What it keeps is the DISTINCT answers:
  # the loop turns over thousands of times while a reload runs, and every one of them says the same
  # thing unless something is wrong - which is the only thing the caller asks about.
  defp watch_lookups(report_to, page_module, answers) do
    receive do
      {:report, ^report_to} -> send(report_to, {:answers, answers})
    after
      0 -> watch_lookups(report_to, page_module, MapSet.put(answers, lookup(page_module)))
    end
  end

  setup do
    setup_sync_page_types(SyncPageTypesStub, false)

    dump(%{
      MyApp.BoardPage => [MyApp.Card, MyApp.Column],
      MyApp.QuietPage => [],
      MyApp.RemovedPage => [MyApp.Gone]
    })

    :ok
  end

  describe "init/1" do
    test "reads the types the build worked out" do
      assert init(nil) == {:ok, nil}

      assert ETS.get_all(SyncPageTypesStub.ets_table_name()) == %{
               MyApp.BoardPage => [MyApp.Card, MyApp.Column],
               MyApp.QuietPage => [],
               MyApp.RemovedPage => [MyApp.Gone]
             }
    end
  end

  describe "lookup/1" do
    setup do
      init(nil)

      :ok
    end

    test "returns the types a page reads" do
      assert lookup(MyApp.BoardPage) == [MyApp.Card, MyApp.Column]
    end

    test "returns nothing for a page reading none" do
      assert lookup(MyApp.QuietPage) == []
    end

    test "returns nothing for a module that is not a page of this build" do
      assert lookup(MyApp.NeverCompiled) == []
    end
  end

  describe "reload/0" do
    test "picks up types the build worked out since" do
      init(nil)

      dump(%{MyApp.BoardPage => [MyApp.Lane]})

      reload()

      assert lookup(MyApp.BoardPage) == [MyApp.Lane]
    end

    # What this guards is the moment between clearing and filling. A session that looked in there
    # would be handed no types for a page that has them, and fill its page's rows in no particular
    # place.
    test "never answers with nothing for a page it holds, however often it is reloaded" do
      init(nil)

      test_pid = self()
      reader = spawn_link(fn -> watch_lookups(test_pid, MyApp.BoardPage, MapSet.new()) end)

      Enum.each(1..200, fn _round -> reload() end)

      send(reader, {:report, self()})
      assert_receive {:answers, answers}

      assert answers == MapSet.new([[MyApp.Card, MyApp.Column]])
    end

    test "forgets a page the build no longer has" do
      init(nil)

      assert lookup(MyApp.RemovedPage) == [MyApp.Gone]

      dump(%{MyApp.BoardPage => [MyApp.Card, MyApp.Column]})

      reload()

      assert lookup(MyApp.RemovedPage) == []
    end
  end

  describe "dump_path/0" do
    test "reads from the build directory" do
      assert PageTypes.dump_path() ==
               Path.join([Reflection.build_dir(), Reflection.page_types_plt_dump_file_name()])
    end
  end
end
