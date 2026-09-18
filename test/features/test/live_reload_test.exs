defmodule HologramFeatureTests.LiveReloadTest do
  # Not async: a live reload event reaches every tab in the VM, and a page's digest is
  # swapped in the registry every tab reads from.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Assets.PageDigestRegistry
  alias Hologram.Commons.PLT
  alias HologramFeatureTests.LiveReload.Page1
  alias HologramFeatureTests.LiveReload.Page2

  # How long a tab has to not reload before it counts as not reloading.
  @no_reload_wait_ms 1_000

  @reload_timeout_ms 10_000

  defp broadcast_live_reload(message) do
    Phoenix.PubSub.broadcast(Hologram.PubSub, "hologram_live_reload", message)
  end

  # Serves the page under another digest, as the server does once a live reload has rebuilt it:
  # its bundle is copied under the new digest (same code, a new name) and the registry names the
  # copy. Both are undone when the test exits.
  defp give_page_another_digest(page_module) do
    table_name = PageDigestRegistry.ets_table_name()
    plt = %PLT{table_name: table_name, table_ref: :ets.whereis(table_name)}

    old_digest = PageDigestRegistry.lookup(page_module)

    new_digest =
      16
      |> :crypto.strong_rand_bytes()
      |> Base.encode16(case: :lower)

    static_dir = Application.app_dir(:hologram_feature_tests, "priv/static/hologram")
    old_bundle_path = Path.join(static_dir, "page-#{old_digest}.js")
    new_bundle_path = Path.join(static_dir, "page-#{new_digest}.js")

    File.cp!(old_bundle_path, new_bundle_path)
    File.cp!(old_bundle_path <> ".map", new_bundle_path <> ".map")
    PLT.put(plt, page_module, new_digest)

    on_exit(fn ->
      PLT.put(plt, page_module, old_digest)
      File.rm(new_bundle_path)
      File.rm(new_bundle_path <> ".map")
    end)
  end

  # Every document load renders a new instance id, an in-app navigation keeps it. Read directly
  # from the driver, since the tab may be between two documents when asked.
  defp read_instance_id(session) do
    case session.driver.execute_script(session, "return globalThis.Hologram.instanceId;") do
      {:ok, instance_id} -> instance_id
      _error -> nil
    end
  end

  defp wait_for_new_document(session, old_instance_id, start_time \\ nil) do
    start_time = start_time || System.monotonic_time(:millisecond)
    instance_id = read_instance_id(session)

    cond do
      instance_id not in [nil, old_instance_id] ->
        session

      System.monotonic_time(:millisecond) - start_time > @reload_timeout_ms ->
        flunk("The tab did not load a new document within #{@reload_timeout_ms} ms")

      true ->
        Process.sleep(100)
        wait_for_new_document(session, old_instance_id, start_time)
    end
  end

  describe "reload event" do
    feature "a tab on a rebuilt page reloads", %{session: session} do
      session = visit(session, Page1)
      instance_id = current_instance_id(session)

      broadcast_live_reload({:reload, [Page1]})

      session
      |> wait_for_new_document(instance_id)
      |> assert_page(Page1)
    end

    feature "a tab on another page does not reload", %{session: session} do
      session = visit(session, Page2)
      instance_id = current_instance_id(session)

      broadcast_live_reload({:reload, [Page1]})
      Process.sleep(@no_reload_wait_ms)

      assert current_instance_id(session) == instance_id
    end

    feature "every tab reloads when the runtime bundle was rebuilt", %{session: session} do
      session = visit(session, Page2)
      instance_id = current_instance_id(session)

      broadcast_live_reload({:reload, :all})

      session
      |> wait_for_new_document(instance_id)
      |> assert_page(Page2)
    end
  end

  describe "compilation error event" do
    feature "shows the compilation error", %{session: session} do
      session = visit(session, Page1)

      broadcast_live_reload({:compilation_error, [[%{text: "boom", tone: "banner"}]]})

      assert_text(session, css("#hologram-live-reload-error-overlay"), "boom")
    end
  end

  describe "navigating to a page whose code the tab holds" do
    feature "loads the page afresh when the server has rebuilt it since", %{session: session} do
      session =
        session
        |> visit(Page1)
        |> click(link("Page 2 link"))
        |> assert_page(Page2)
        |> click(link("Page 1 link"))
        |> assert_page(Page1)

      instance_id = current_instance_id(session)

      give_page_another_digest(Page2)

      session
      |> click(link("Page 2 link"))
      |> wait_for_new_document(instance_id)
      |> assert_page(Page2)
    end

    feature "navigates in the app when the page is current", %{session: session} do
      session =
        session
        |> visit(Page1)
        |> click(link("Page 2 link"))
        |> assert_page(Page2)
        |> click(link("Page 1 link"))
        |> assert_page(Page1)

      instance_id = current_instance_id(session)

      session
      |> click(link("Page 2 link"))
      |> assert_page(Page2)

      assert current_instance_id(session) == instance_id
    end
  end

  describe "going back to a page" do
    feature "reloads it with fresh state when its snapshot was taken with other code", %{
      session: session
    } do
      session =
        session
        |> visit(Page1)
        |> click(button("Increment"))
        |> assert_text(css("#count"), "1")
        |> click(link("Page 2 link"))
        |> assert_page(Page2)

      instance_id = current_instance_id(session)

      give_page_another_digest(Page1)

      session
      |> go_back()
      |> wait_for_new_document(instance_id)
      |> assert_page(Page1)
      |> assert_text(css("#count"), "0")
    end

    feature "restores its state when its snapshot fits the code", %{session: session} do
      session =
        session
        |> visit(Page1)
        |> click(button("Increment"))
        |> assert_text(css("#count"), "1")
        |> click(link("Page 2 link"))
        |> assert_page(Page2)

      instance_id = current_instance_id(session)

      session
      |> go_back()
      |> assert_page(Page1)
      |> assert_text(css("#count"), "1")

      assert current_instance_id(session) == instance_id
    end
  end
end
