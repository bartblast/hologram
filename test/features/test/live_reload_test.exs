defmodule HologramFeatureTests.LiveReloadTest do
  # Not async: a live reload event reaches every tab in the VM, a page's digest is swapped in
  # the registry every tab reads from, and the asset path registry every page is rendered with
  # is restarted.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Assets.ManifestCache
  alias Hologram.Assets.PageDigestRegistry
  alias Hologram.Assets.PathRegistry
  alias Hologram.Commons.PLT
  alias Hologram.Router.Helpers, as: RouterHelpers
  alias HologramFeatureTests.LiveReload.Page1
  alias HologramFeatureTests.LiveReload.Page2
  alias HologramFeatureTests.LiveReload.Page3
  alias HologramFeatureTests.LiveReload.Page4

  # How long a tab has to not reload before it counts as not reloading.
  @no_reload_wait_ms 1_000

  @overlay css("#hologram-live-reload-error-overlay")

  @phoenix_reload_frame css(~s(iframe[src*="/phoenix/live_reload/frame"]))

  @reload_timeout_ms 10_000

  # The stylesheet Page4's layout links through asset_path/1.
  @digest_stylesheet_static_path "assets/live_reload_digest.css"

  defp broadcast_live_reload(message) do
    Phoenix.PubSub.broadcast(Hologram.PubSub, "hologram_live_reload", message)
  end

  defp bundle_static_path(page_module, digest) do
    static_dir = Application.app_dir(:hologram_feature_tests, "priv/static")
    Path.join(static_dir, RouterHelpers.page_bundle_path(page_module, digest))
  end

  defp computed_color(session) do
    script_result(session, "return getComputedStyle(document.getElementById('styled')).color;")
  end

  # The static path `mix phx.digest` gives a copy of the Page4 stylesheet in the given color: the
  # stylesheet's own, with the MD5 of the copy's content in it.
  defp digest_stylesheet_copy_static_path(color) do
    digest =
      color
      |> stylesheet_css()
      |> :erlang.md5()
      |> Base.encode16(case: :lower)

    "assets/live_reload_digest-#{digest}.css"
  end

  # Serves the page under another digest, as the server does once a live reload has rebuilt it:
  # its bundle is copied under the new digest (same code, a new name) and the registry names the
  # copy. Both are undone when the test exits.
  defp give_page_another_digest(page_module) do
    table_name = PageDigestRegistry.ets_table_name()
    plt = %PLT{table_name: table_name, table_ref: :ets.whereis(table_name)}

    old_digest = PageDigestRegistry.lookup(page_module)

    # 5 random bytes encode to 8 chars of esbuild's base32 alphabet, the shape of a real digest.
    new_digest =
      5
      |> :crypto.strong_rand_bytes()
      |> Base.encode32()

    old_bundle_path = bundle_static_path(page_module, old_digest)
    new_bundle_path = bundle_static_path(page_module, new_digest)

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

  # Rebuilds the asset paths from the static dir, as the server's start does: the asset path
  # registry, restarted, and the asset manifest the pages are rendered with. The registry ends up as
  # live reload's update after a change to the static files leaves it, and the test app runs no live
  # reload.
  defp rebuild_asset_paths do
    :ok = Supervisor.terminate_child(Hologram.Supervisor, PathRegistry)
    {:ok, _pid} = Supervisor.restart_child(Hologram.Supervisor, PathRegistry)

    ManifestCache.reload()
  end

  defp static_file_path(static_path) do
    Application.app_dir(:hologram_feature_tests, Path.join("priv/static", static_path))
  end

  defp stylesheet_css(color) do
    "#styled { color: #{color}; }\n"
  end

  # The stylesheet Page3's layout links, written through the app dir the server serves static files
  # from. Removed when the test exits.
  defp stylesheet_path do
    Application.app_dir(:hologram_feature_tests, "priv/static/assets/live_reload.css")
  end

  defp wait_for_computed_color(session, color, start_time \\ nil) do
    start_time = start_time || System.monotonic_time(:millisecond)

    cond do
      computed_color(session) == color ->
        session

      System.monotonic_time(:millisecond) - start_time > @reload_timeout_ms ->
        flunk(
          "The text did not turn #{color} within #{@reload_timeout_ms} ms, it is #{computed_color(session)}"
        )

      true ->
        Process.sleep(100)
        wait_for_computed_color(session, color, start_time)
    end
  end

  # The path the stylesheet link Page4 rendered points at, read once the link it was kept as is the
  # only one left, with no swap copy next to it, and holds the given path.
  defp wait_for_digest_stylesheet_path(session, path, start_time \\ nil) do
    start_time = start_time || System.monotonic_time(:millisecond)

    linked_path =
      script_result(session, """
      const links = document.querySelectorAll('link[href*="live_reload_digest"]');
      const link = globalThis.__digestStylesheetLink;

      return links.length === 1 && links[0] === link ? new URL(link.href).pathname : null;
      """)

    cond do
      linked_path == path ->
        session

      System.monotonic_time(:millisecond) - start_time > @reload_timeout_ms ->
        flunk("The stylesheet did not link #{path} within #{@reload_timeout_ms} ms")

      true ->
        Process.sleep(100)
        wait_for_digest_stylesheet_path(session, path, start_time)
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

  # A swap is done once the copy that kept the page styled is gone and the link the page rendered
  # holds the fresh URL.
  defp wait_for_stylesheet_swapped(session, start_time \\ nil) do
    start_time = start_time || System.monotonic_time(:millisecond)

    swapped? =
      script_result(session, """
      const links = document.querySelectorAll('link[href*="live_reload.css"]');
      const link = globalThis.__stylesheetLink;

      return links.length === 1 && links[0] === link && link.href.includes("_hologram_css");
      """)

    cond do
      swapped? ->
        session

      System.monotonic_time(:millisecond) - start_time > @reload_timeout_ms ->
        flunk("The stylesheet swap did not finish within #{@reload_timeout_ms} ms")

      true ->
        Process.sleep(100)
        wait_for_stylesheet_swapped(session, start_time)
    end
  end

  defp write_digest_stylesheet(color) do
    @digest_stylesheet_static_path
    |> static_file_path()
    |> File.write!(stylesheet_css(color))
  end

  # Writes a copy of the Page4 stylesheet in the given color, under the name `mix phx.digest` gives
  # it, and returns the copy's static path.
  defp write_digest_stylesheet_copy(color) do
    copy_static_path = digest_stylesheet_copy_static_path(color)

    copy_static_path
    |> static_file_path()
    |> File.write!(stylesheet_css(color))

    copy_static_path
  end

  defp write_stylesheet(color) do
    File.write!(stylesheet_path(), "#styled { color: #{color}; }\n")
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

  describe "css changed event" do
    setup do
      assets_dir = Path.dirname(stylesheet_path())
      File.mkdir_p!(assets_dir)
      write_stylesheet("rgb(255, 0, 0)")

      on_exit(fn ->
        File.rm(stylesheet_path())
        # Left alone when it holds anything else.
        File.rmdir(assets_dir)
      end)
    end

    feature "applies the new CSS without reloading the tab", %{session: session} do
      session =
        session
        |> visit(Page3)
        |> wait_for_computed_color("rgb(255, 0, 0)")

      instance_id = current_instance_id(session)

      # Kept to tell that the swap gives the link element the page rendered the fresh URL rather
      # than replacing it.
      execute_script(session, """
      globalThis.__stylesheetLink = document.querySelector('link[href^="/assets/live_reload.css"]');
      """)

      write_stylesheet("rgb(0, 0, 255)")
      broadcast_live_reload(:css_changed)

      session
      |> wait_for_computed_color("rgb(0, 0, 255)")
      |> wait_for_stylesheet_swapped()

      assert computed_color(session) == "rgb(0, 0, 255)"

      Process.sleep(@no_reload_wait_ms)

      assert current_instance_id(session) == instance_id
    end
  end

  describe "digested stylesheet" do
    setup do
      assets_dir =
        @digest_stylesheet_static_path
        |> static_file_path()
        |> Path.dirname()

      File.mkdir_p!(assets_dir)

      on_exit(fn ->
        assets_dir
        |> File.ls!()
        |> Enum.filter(&String.starts_with?(&1, "live_reload_digest"))
        |> Enum.map(&Path.join(assets_dir, &1))
        |> Enum.each(&File.rm!/1)

        # Left alone when it holds anything else.
        File.rmdir(assets_dir)

        rebuild_asset_paths()
      end)
    end

    feature "links the plain file over a digested copy that no longer holds its content", %{
      session: session
    } do
      write_digest_stylesheet("rgb(0, 128, 0)")
      write_digest_stylesheet_copy("rgb(255, 165, 0)")
      rebuild_asset_paths()

      session
      |> visit(Page4)
      |> wait_for_computed_color("rgb(0, 128, 0)")

      assert script_result(session, """
             return document.querySelector('link[href*="live_reload_digest"]').getAttribute("href");
             """) == "/" <> @digest_stylesheet_static_path
    end

    feature "swaps a stylesheet whose digested copy no longer holds its content to the plain file without reloading the tab",
            %{session: session} do
      write_digest_stylesheet("rgb(128, 0, 128)")
      copy_static_path = write_digest_stylesheet_copy("rgb(128, 0, 128)")
      rebuild_asset_paths()

      session =
        session
        |> visit(Page4)
        |> wait_for_computed_color("rgb(128, 0, 128)")

      instance_id = current_instance_id(session)

      assert script_result(session, """
             return document.querySelector('link[href*="live_reload_digest"]').getAttribute("href");
             """) == "/" <> copy_static_path

      execute_script(session, """
      globalThis.__digestStylesheetLink = document.querySelector('link[href*="live_reload_digest"]');
      """)

      write_digest_stylesheet("rgb(0, 128, 128)")
      rebuild_asset_paths()
      broadcast_live_reload(:css_changed)

      session
      |> wait_for_computed_color("rgb(0, 128, 128)")
      |> wait_for_digest_stylesheet_path("/" <> @digest_stylesheet_static_path)

      assert computed_color(session) == "rgb(0, 128, 128)"

      Process.sleep(@no_reload_wait_ms)

      assert current_instance_id(session) == instance_id

      # A render after the swap links the plain file too: the tab took the new asset paths.
      session
      |> click(button("Increment"))
      |> assert_has(css("#count", text: "1"))

      assert script_result(session, """
             const links = document.querySelectorAll('link[href*="live_reload_digest"]');

             return Array.from(links, (link) => new URL(link.href).pathname);
             """) == ["/" <> @digest_stylesheet_static_path]

      assert computed_color(session) == "rgb(0, 128, 128)"
    end
  end

  describe "Phoenix's live reload frame" do
    # The server sends the page with the frame, as Phoenix's live reload plug does in dev. Until
    # #1380 the first render removes it anyway, along with every other node it did not render.
    feature "is removed from the page", %{session: session} do
      session = visit(session, Page3)

      assert script_result(session, "return fetch(location.pathname).then(r => r.text());") =~
               "/phoenix/live_reload/frame"

      refute_has(session, @phoenix_reload_frame)
    end
  end

  describe "compilation error event" do
    feature "shows the compilation error", %{session: session} do
      session = visit(session, Page1)

      broadcast_live_reload({:compilation_error, [[%{text: "boom", tone: "banner"}]]})

      assert_text(session, @overlay, "boom")
    end
  end

  describe "compiled event" do
    feature "takes the compilation error down without reloading the tab", %{session: session} do
      session = visit(session, Page1)
      instance_id = current_instance_id(session)

      broadcast_live_reload({:compilation_error, [[%{text: "boom", tone: "banner"}]]})
      assert_has(session, @overlay)

      broadcast_live_reload(:compiled)
      refute_has(session, @overlay)
      Process.sleep(@no_reload_wait_ms)

      assert current_instance_id(session) == instance_id
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

    # Returning from outside the app loads a new document, which restores the page's snapshot
    # rather than mounting from mount data. The snapshot it saves on leaving has to carry the
    # document's digest all the same, or a later rebuild would go unnoticed on the way back.
    feature "reloads it when it was rebuilt since a document restored it", %{session: session} do
      session =
        session
        |> visit(Page1)
        |> click(link("Page 2 link"))
        |> assert_page(Page2)
        |> visit("/external")
        |> assert_text("External Page")
        |> go_back()
        |> assert_page(Page2)
        |> click(link("Page 1 link"))
        |> assert_page(Page1)

      instance_id = current_instance_id(session)

      give_page_another_digest(Page2)

      session
      |> go_back()
      |> wait_for_new_document(instance_id)
      |> assert_page(Page2)
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
