# Note: These tests focus on the GenServer message handling logic and do not
# test the actual Phoenix.CodeReloader or Mix.Tasks.Compile.Hologram integration,
# as those require the full Hologram/Phoenix application infrastructure.
# Some tests suppress Logger output to avoid expected error messages from
# Phoenix.CodeReloader when testing with nil endpoints.

defmodule Hologram.LiveReloadTest do
  use Hologram.Test.BasicCase, async: false

  import ExUnit.CaptureLog
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Assets.ManifestCache, as: AssetManifestCache
  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.Commons.ETS
  alias Hologram.LiveReload
  alias Hologram.Realtime.SubscriptionRegistry

  use_module_stub :asset_manifest_cache
  use_module_stub :asset_path_registry
  use_module_stub :chunk_registry
  use_module_stub :page_digest_registry
  use_module_stub :page_module_resolver

  @asset_debounce_delay LiveReload.asset_debounce_delay()
  @debounce_delay LiveReload.debounce_delay()
  @static_dir "/app/priv/static"
  @file_path Path.join([@fixtures_dir, "live_reload", "module_1.ex"])

  defp asset_event(file_path, state, events \\ [:modified]) do
    LiveReload.handle_info({:file_event, self(), {file_path, events}}, state)
  end

  # Has the started live reload process see a CSS change, and waits for the tabs to be told.
  defp change_css(pid) do
    send(pid, {:file_event, self(), {"#{@static_dir}/assets/app.css", [:modified]}})
    assert_receive :css_changed, @asset_debounce_delay + 500
  end

  # Has the started live reload process see a change to an asset other than CSS, and waits for the
  # tabs to be told.
  defp change_js(pid) do
    send(pid, {:file_event, self(), {"#{@static_dir}/assets/app.js", [:modified]}})
    assert_receive {:reload, :all}, @asset_debounce_delay + 500
  end

  defp static_dir_and_watched_dirs(project_dir) do
    File.cd!(project_dir, fn ->
      {LiveReload.watched_static_dir(), LiveReload.watcher_opts({:unix, :linux})[:dirs]}
    end)
  end

  setup do
    wait_for_process_cleanup(Hologram.PubSub)
    start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

    :ok
  end

  test "asset_debounce_delay/0" do
    result = LiveReload.asset_debounce_delay()

    assert is_integer(result)
    assert result > 0
  end

  test "debounce_delay/0" do
    result = LiveReload.debounce_delay()

    assert is_integer(result)
    assert result > 0
  end

  describe "handle_info/2, file events" do
    setup do
      [state: LiveReload.initial_state(nil)]
    end

    test "ignores :stop file events", %{state: state} do
      result = LiveReload.handle_info({:file_event, self(), :stop}, state)
      assert result == {:noreply, state}
    end

    test "starts debounce timer for .ex file changes", %{state: state} do
      result = LiveReload.handle_info({:file_event, self(), {@file_path, [:modified]}}, state)

      assert {:noreply, new_state} = result
      assert is_reference(new_state.timer_ref)
    end

    test "starts debounce timer for .holo file changes", %{state: state} do
      holo_file = Path.join([@fixtures_dir, "live_reload", "module_1.holo"])
      result = LiveReload.handle_info({:file_event, self(), {holo_file, [:modified]}}, state)

      assert {:noreply, new_state} = result
      assert is_reference(new_state.timer_ref)
    end

    test "processes :renamed events for .ex files", %{state: state} do
      result = LiveReload.handle_info({:file_event, self(), {@file_path, [:renamed]}}, state)

      assert {:noreply, new_state} = result
      assert is_reference(new_state.timer_ref)
    end

    test "processes :renamed events for .holo files", %{state: state} do
      holo_file = Path.join([@fixtures_dir, "live_reload", "module_1.holo"])
      result = LiveReload.handle_info({:file_event, self(), {holo_file, [:renamed]}}, state)

      assert {:noreply, new_state} = result
      assert is_reference(new_state.timer_ref)
    end

    test "ignores irrelevant file types", %{state: state} do
      irrelevant_files = [
        Path.join([@fixtures_dir, "live_reload", "file.css"]),
        Path.join([@fixtures_dir, "live_reload", "file.json"]),
        Path.join([@fixtures_dir, "live_reload", "file.md"]),
        Path.join([@fixtures_dir, "live_reload", "file.txt"]),
        Path.join([@fixtures_dir, "live_reload", "backup.holo~"]),
        Path.join([@fixtures_dir, "live_reload", ".#temp.holo"])
      ]

      for file_path <- irrelevant_files do
        result = LiveReload.handle_info({:file_event, self(), {file_path, [:modified]}}, state)
        assert result == {:noreply, state}
      end
    end

    test "cancels existing timer and starts new one", %{state: state} do
      timer_ref = Process.send_after(self(), :dummy, 5_000)
      state_with_timer = %{state | timer_ref: timer_ref}

      result =
        LiveReload.handle_info({:file_event, self(), {@file_path, [:modified]}}, state_with_timer)

      assert {:noreply, new_state} = result
      assert new_state.timer_ref != timer_ref
      assert is_reference(new_state.timer_ref)
    end

    test "debounce timer sends debounced_reload message with target file after delay", %{
      state: state
    } do
      LiveReload.handle_info({:file_event, self(), {@file_path, [:modified]}}, state)

      # For .ex files, the target file is the same as the original file
      assert_receive {:debounced_reload, @file_path}, @debounce_delay + 100
    end

    test "debounce timer sends debounced_reload message with .ex target for .holo files", %{
      state: state
    } do
      holo_file = Path.join([@fixtures_dir, "live_reload", "module_1.holo"])
      ex_file = Path.join([@fixtures_dir, "live_reload", "module_1.ex"])

      LiveReload.handle_info({:file_event, self(), {holo_file, [:modified]}}, state)

      # For .holo files, the target file should be the corresponding .ex file
      assert_receive {:debounced_reload, ^ex_file}, @debounce_delay + 100
    end

    test "multiple file events are debounced", %{state: state_0} do
      # First event
      {:noreply, state_1} =
        LiveReload.handle_info({:file_event, self(), {@file_path, [:modified]}}, state_0)

      timer_ref_1 = state_1.timer_ref

      # Second event should cancel the first timer
      {:noreply, state_2} =
        LiveReload.handle_info({:file_event, self(), {@file_path, [:modified]}}, state_1)

      timer_ref_2 = state_2.timer_ref

      assert timer_ref_2 != timer_ref_1
      assert is_reference(timer_ref_2)

      # Should receive only one debounced message
      assert_receive {:debounced_reload, @file_path}, @debounce_delay + 100
      refute_receive {:debounced_reload, @file_path}, 100
    end
  end

  describe "handle_info/2, asset file events" do
    setup do
      [state: LiveReload.initial_state(nil)]
    end

    test "a CSS file in priv/static starts the asset timer", %{state: state} do
      assert {:noreply, new_state} = asset_event("#{@static_dir}/assets/app.css", state)

      assert new_state.asset_change == :css
      assert is_reference(new_state.asset_timer_ref)
      assert new_state.changed_static_paths == MapSet.new(["assets/app.css"])
      assert new_state.timer_ref == nil
    end

    test "a CSS file right in priv/static counts too", %{state: state} do
      assert {:noreply, new_state} = asset_event("#{@static_dir}/app.css", state)

      assert new_state.asset_change == :css
      assert new_state.changed_static_paths == MapSet.new(["app.css"])
    end

    test "other asset types in priv/static start the asset timer", %{state: state} do
      for extension <- ~w(js png jpeg jpg gif svg) do
        assert {:noreply, new_state} =
                 asset_event("#{@static_dir}/assets/file.#{extension}", state)

        assert new_state.asset_change == :other
        assert is_reference(new_state.asset_timer_ref)
        assert new_state.changed_static_paths == MapSet.new(["assets/file.#{extension}"])
      end
    end

    test "ignores Hologram's bundles", %{state: state} do
      assert asset_event("#{@static_dir}/hologram/page-ABCDEFGH.js", state) == {:noreply, state}
    end

    test "ignores uploads", %{state: state} do
      assert asset_event("#{@static_dir}/uploads/photo.png", state) == {:noreply, state}
    end

    test "other files in priv/static start the asset timer with no change the tabs are told about",
         %{state: state} do
      for file_name <- ~w(app.js.map robots.txt cache_manifest.json app.css.gz font.woff2) do
        assert {:noreply, new_state} = asset_event("#{@static_dir}/assets/#{file_name}", state)

        assert new_state.asset_change == nil
        assert is_reference(new_state.asset_timer_ref)
        assert new_state.changed_static_paths == MapSet.new(["assets/#{file_name}"])
      end
    end

    test "a path with no extension in priv/static, such as a dir, created, removed or renamed starts the asset timer, reloading every tab",
         %{state: state} do
      for static_path <- ~w(assets/fonts assets/LICENSE),
          events <- [[:created], [:removed], [:renamed], [:deleted], [:moved_from], [:moved_to]] do
        assert {:noreply, new_state} =
                 asset_event("#{@static_dir}/#{static_path}", state, events)

        assert new_state.asset_change == :other
        assert is_reference(new_state.asset_timer_ref)
        assert new_state.changed_static_paths == MapSet.new([static_path])
      end
    end

    test "a path with no extension in priv/static, such as a dir, only modified starts the asset timer with no change the tabs are told about",
         %{state: state} do
      assert {:noreply, new_state} = asset_event("#{@static_dir}/assets", state, [:modified])

      assert new_state.asset_change == nil
      assert is_reference(new_state.asset_timer_ref)
      assert new_state.changed_static_paths == MapSet.new(["assets"])
    end

    test "priv/static itself created, removed or renamed starts the asset timer, reloading every tab",
         %{state: state} do
      assert {:noreply, new_state} = asset_event(@static_dir, state, [:created])

      assert new_state.asset_change == :other
      assert is_reference(new_state.asset_timer_ref)
      assert new_state.changed_static_paths == MapSet.new([""])
    end

    test "priv/static itself only modified starts the asset timer with no change the tabs are told about",
         %{state: state} do
      assert {:noreply, new_state} = asset_event(@static_dir, state, [:modified])

      assert new_state.asset_change == nil
      assert is_reference(new_state.asset_timer_ref)
      assert new_state.changed_static_paths == MapSet.new([""])
    end

    test "ignores the hologram and uploads dirs themselves", %{state: state} do
      assert asset_event("#{@static_dir}/hologram", state) == {:noreply, state}
      assert asset_event("#{@static_dir}/uploads", state) == {:noreply, state}
    end

    test "a file the tabs aren't told about leaves a CSS change as it is", %{state: state_0} do
      {:noreply, state_1} = asset_event("#{@static_dir}/assets/app.css", state_0)
      {:noreply, state_2} = asset_event("#{@static_dir}/assets/font.woff2", state_1)

      assert state_2.asset_change == :css
      assert state_2.changed_static_paths == MapSet.new(["assets/app.css", "assets/font.woff2"])
    end

    test "ignores asset types outside priv/static", %{state: state} do
      assert asset_event("/app/assets/css/app.css", state) == {:noreply, state}
      assert asset_event("/app/lib/app/static/app.js", state) == {:noreply, state}
    end

    test "goes by the last priv/static in the path", %{state: state} do
      project_dir = "/srv/priv/static/app"

      assert asset_event("#{project_dir}/priv/static/hologram/page-ABCDEFGH.js", state) ==
               {:noreply, state}

      assert {:noreply, %{asset_change: :css}} =
               asset_event("#{project_dir}/priv/static/assets/app.css", state)
    end

    test "leaves a pending code reload alone", %{state: state} do
      timer_ref = Process.send_after(self(), {:debounced_reload, @file_path}, @debounce_delay)
      state = %{state | timer_ref: timer_ref}

      assert {:noreply, new_state} = asset_event("#{@static_dir}/assets/app.css", state)

      assert new_state.timer_ref == timer_ref
      assert_receive {:debounced_reload, @file_path}, @debounce_delay + 100
    end

    test "a source file starts the code timer, not the asset timer", %{state: state} do
      assert {:noreply, new_state} = asset_event(@file_path, state)

      assert is_reference(new_state.timer_ref)
      assert new_state.asset_timer_ref == nil
      assert new_state.asset_change == nil
    end

    test "changes in quick succession make one", %{state: state_0} do
      {:noreply, state_1} = asset_event("#{@static_dir}/assets/app.css", state_0)
      {:noreply, state_2} = asset_event("#{@static_dir}/assets/admin.css", state_1)

      assert state_2.asset_timer_ref == state_1.asset_timer_ref
      assert state_2.asset_change == :css

      assert_receive :debounced_asset_change, @asset_debounce_delay + 100
      refute_receive :debounced_asset_change, 100
    end

    test "a change other than CSS outweighs a CSS one", %{state: state_0} do
      {:noreply, state_1} = asset_event("#{@static_dir}/assets/app.css", state_0)
      {:noreply, state_2} = asset_event("#{@static_dir}/assets/app.js", state_1)
      {:noreply, state_3} = asset_event("#{@static_dir}/assets/app.css", state_2)

      assert state_3.asset_change == :other
    end
  end

  describe "handle_info/2, :debounced_asset_change" do
    setup do
      setup_asset_path_registry(AssetPathRegistryStub)
      setup_asset_manifest_cache(AssetManifestCacheStub)

      Phoenix.PubSub.subscribe(Hologram.PubSub, "hologram_live_reload")

      [state: LiveReload.initial_state(nil)]
    end

    test "updates the asset path registry and the asset manifest with the changed files",
         %{state: state} do
      file_path = Path.join(AssetPathRegistryStub.static_dir(), "assets/new.css")

      file_path
      |> Path.dirname()
      |> File.mkdir_p!()

      File.write!(file_path, "")

      state = %{
        state
        | asset_change: :css,
          asset_timer_ref: make_ref(),
          changed_static_paths: MapSet.new(["assets/new.css"])
      }

      assert {:noreply, %{changed_static_paths: changed_static_paths}} =
               LiveReload.handle_info(:debounced_asset_change, state)

      assert changed_static_paths == MapSet.new()
      assert AssetPathRegistry.lookup("assets/new.css") == {:ok, "/assets/new.css"}
      assert AssetManifestCache.get_manifest_js() =~ ~s("assets/new.css": "/assets/new.css")

      assert_receive :css_changed
    end

    test "a change to files the tabs aren't told about updates the asset path registry and leaves the tabs alone",
         %{state: state} do
      file_path = Path.join(AssetPathRegistryStub.static_dir(), "assets/font.woff2")

      file_path
      |> Path.dirname()
      |> File.mkdir_p!()

      File.write!(file_path, "")

      state = %{
        state
        | asset_timer_ref: make_ref(),
          changed_static_paths: MapSet.new(["assets/font.woff2"])
      }

      assert LiveReload.handle_info(:debounced_asset_change, state) ==
               {:noreply, %{state | asset_timer_ref: nil, changed_static_paths: MapSet.new()}}

      assert AssetPathRegistry.lookup("assets/font.woff2") == {:ok, "/assets/font.woff2"}

      refute_receive :css_changed
      refute_receive {:reload, _pages}
    end

    test "a CSS change tells the tabs to swap their stylesheets", %{state: state} do
      state = %{state | asset_change: :css, asset_timer_ref: make_ref()}

      assert LiveReload.handle_info(:debounced_asset_change, state) ==
               {:noreply, %{state | asset_change: nil, asset_timer_ref: nil, css_version: 2}}

      assert_receive :css_changed
      refute_receive {:reload, _pages}
    end

    test "any other change reloads every tab", %{state: state} do
      state = %{state | asset_change: :other, asset_timer_ref: make_ref()}

      assert LiveReload.handle_info(:debounced_asset_change, state) ==
               {:noreply, %{state | asset_change: nil, asset_timer_ref: nil, reload_version: 1}}

      assert_receive {:reload, :all}
      refute_receive :css_changed
    end

    test "is independent of a live reload pass and a pending code reload", %{state: state} do
      state = %{
        state
        | asset_change: :css,
          asset_timer_ref: make_ref(),
          outcome: :compiled,
          pass: %{ref: make_ref(), registries_reloaded?: false},
          timer_ref: make_ref()
      }

      assert LiveReload.handle_info(:debounced_asset_change, state) ==
               {:noreply, %{state | asset_change: nil, asset_timer_ref: nil, css_version: 2}}

      assert_receive :css_changed
    end

    test "a change after it starts a new batch", %{state: state_0} do
      {:noreply, state_1} = asset_event("#{@static_dir}/assets/app.js", state_0)

      assert_receive :debounced_asset_change, @asset_debounce_delay + 100
      {:noreply, state_2} = LiveReload.handle_info(:debounced_asset_change, state_1)
      assert_receive {:reload, :all}

      {:noreply, state_3} = asset_event("#{@static_dir}/assets/app.css", state_2)

      assert state_3.asset_change == :css
      assert is_reference(state_3.asset_timer_ref)
      assert state_3.asset_timer_ref != state_1.asset_timer_ref
    end
  end

  describe "open_pages/0" do
    setup do
      wait_for_process_cleanup(SubscriptionRegistry)
      start_supervised!(SubscriptionRegistry)

      wait_for_process_cleanup(LiveReload)
      start_supervised!({LiveReload, watch?: false})

      :ok
    end

    test "lists the page each tab with an SSE connection shows" do
      :ok = SubscriptionRegistry.register_connection("instance-1", self())

      LiveReload.page_rendered("instance-1", Module1)

      assert LiveReload.open_pages() == %{"instance-1" => Module1}
    end

    test "a tab's later render replaces the page it showed" do
      :ok = SubscriptionRegistry.register_connection("instance-1", self())

      LiveReload.page_rendered("instance-1", Module1)
      LiveReload.page_rendered("instance-1", Module2)

      assert LiveReload.open_pages() == %{"instance-1" => Module2}
    end

    test "keeps a tab whose SSE connection has not attached yet" do
      LiveReload.page_rendered("instance-1", Module1)

      assert LiveReload.open_pages() == %{"instance-1" => Module1}
      assert {Module1, missing_since} = :sys.get_state(LiveReload).open_pages["instance-1"]
      assert is_integer(missing_since)
    end

    test "forgets a tab seen without an SSE connection for longer than the grace period" do
      LiveReload.page_rendered("instance-1", Module1)

      long_ago = System.monotonic_time(:millisecond) - 60_000

      :sys.replace_state(LiveReload, fn state ->
        %{state | open_pages: %{"instance-1" => {Module1, long_ago}}}
      end)

      assert LiveReload.open_pages() == %{}
      assert :sys.get_state(LiveReload).open_pages == %{}
    end

    test "forgets the document of a tab it forgets" do
      LiveReload.page_rendered("instance-1", Module1)
      LiveReload.document_rendered("instance-1")
      LiveReload.page_rendered("instance-2", Module2)
      LiveReload.document_rendered("instance-2")

      long_ago = System.monotonic_time(:millisecond) - 60_000

      :sys.replace_state(LiveReload, fn state ->
        put_in(state.open_pages["instance-1"], {Module1, long_ago})
      end)

      LiveReload.open_pages()

      assert :sys.get_state(LiveReload).document_versions == %{"instance-2" => {1, 0}}
    end

    test "keeps the document of a tab first seen through its stream" do
      LiveReload.replay_asset_change(self(), "instance-1")

      LiveReload.open_pages()

      assert :sys.get_state(LiveReload).document_versions == %{"instance-1" => {0, 0}}
    end

    test "a live reload batch forgets the document of a tab it forgets" do
      long_ago = System.monotonic_time(:millisecond) - 60_000

      state = %{
        LiveReload.initial_state(nil)
        | document_versions: %{"instance-1" => {1, 0}},
          open_pages: %{"instance-1" => {Module1, long_ago}}
      }

      assert {:reply, [], new_state} =
               LiveReload.handle_call({:next_batch, MapSet.new(), %{}}, self(), state)

      assert new_state.document_versions == %{}
    end

    test "a tab seen with its SSE connection again is no longer missing" do
      LiveReload.page_rendered("instance-1", Module1)
      LiveReload.open_pages()

      :ok = SubscriptionRegistry.register_connection("instance-1", self())

      assert LiveReload.open_pages() == %{"instance-1" => Module1}
      assert :sys.get_state(LiveReload).open_pages == %{"instance-1" => {Module1, nil}}
    end
  end

  describe "document_rendered/1" do
    test "does nothing when live reload is not running" do
      wait_for_process_cleanup(LiveReload)

      assert LiveReload.document_rendered("instance-1") == :ok
    end
  end

  describe "replay_asset_change/2" do
    test "does nothing when live reload is not running" do
      wait_for_process_cleanup(LiveReload)

      assert LiveReload.replay_asset_change(self(), "instance-1") == :ok
    end
  end

  describe "asset change replay" do
    setup do
      setup_asset_path_registry(AssetPathRegistryStub)
      setup_asset_manifest_cache(AssetManifestCacheStub)

      wait_for_process_cleanup(LiveReload)
      pid = start_supervised!({LiveReload, watch?: false})

      Phoenix.PubSub.subscribe(Hologram.PubSub, "hologram_live_reload")

      [pid: pid]
    end

    test "a stream of a tab whose document rendered before a CSS change is sent it", %{pid: pid} do
      LiveReload.document_rendered("instance-1")
      change_css(pid)

      LiveReload.replay_asset_change(self(), "instance-1")

      assert_receive :css_changed
    end

    test "a stream of a tab whose document rendered after it is not", %{pid: pid} do
      change_css(pid)
      LiveReload.document_rendered("instance-1")

      LiveReload.replay_asset_change(self(), "instance-1")

      refute_receive :css_changed, 100
    end

    test "a stream of a tab rendered with no change since is not" do
      LiveReload.document_rendered("instance-1")

      LiveReload.replay_asset_change(self(), "instance-1")

      refute_receive :css_changed, 100
    end

    test "a stream of a tab it knows nothing of is sent it, even with no change" do
      LiveReload.replay_asset_change(self(), "instance-1")

      assert_receive :css_changed
    end

    test "a change is sent again to the tab's next stream", %{pid: pid} do
      LiveReload.document_rendered("instance-1")
      change_css(pid)

      LiveReload.replay_asset_change(self(), "instance-1")
      assert_receive :css_changed

      LiveReload.replay_asset_change(self(), "instance-1")
      assert_receive :css_changed
    end

    test "a stream of a tab whose document rendered before a change other than CSS is sent a reload",
         %{pid: pid} do
      LiveReload.document_rendered("instance-1")
      change_js(pid)

      LiveReload.replay_asset_change(self(), "instance-1")

      assert_receive {:reload, :all}
    end

    test "a reload is sent again to the tab's next stream", %{pid: pid} do
      LiveReload.document_rendered("instance-1")
      change_js(pid)

      LiveReload.replay_asset_change(self(), "instance-1")
      assert_receive {:reload, :all}

      LiveReload.replay_asset_change(self(), "instance-1")
      assert_receive {:reload, :all}
    end

    test "a stream of a tab whose document rendered after it is sent no reload", %{pid: pid} do
      change_js(pid)
      LiveReload.document_rendered("instance-1")

      LiveReload.replay_asset_change(self(), "instance-1")

      refute_receive {:reload, :all}, 100
    end

    test "a stream of a tab it knows nothing of is sent no reload", %{pid: pid} do
      change_js(pid)

      LiveReload.replay_asset_change(self(), "instance-1")

      assert_receive :css_changed
      refute_receive {:reload, :all}, 100
    end

    test "a tab it knows nothing of is sent the CSS change again by its next stream" do
      LiveReload.replay_asset_change(self(), "instance-1")
      assert_receive :css_changed

      LiveReload.replay_asset_change(self(), "instance-1")
      assert_receive :css_changed
    end

    test "a tab it knows nothing of is sent a reload it misses after its first stream", %{
      pid: pid
    } do
      LiveReload.replay_asset_change(self(), "instance-1")
      assert_receive :css_changed

      change_js(pid)

      LiveReload.replay_asset_change(self(), "instance-1")

      assert_receive {:reload, :all}
    end

    test "a stream of a tab whose document rendered before a CSS change and another change is sent only a reload",
         %{pid: pid} do
      LiveReload.document_rendered("instance-1")
      change_css(pid)
      change_js(pid)

      LiveReload.replay_asset_change(self(), "instance-1")

      assert_receive {:reload, :all}
      refute_receive :css_changed, 100
    end

    test "a stream of a tab whose document rendered between a change other than CSS and a CSS change is sent only the CSS change",
         %{pid: pid} do
      change_js(pid)
      LiveReload.document_rendered("instance-1")
      change_css(pid)

      LiveReload.replay_asset_change(self(), "instance-1")

      assert_receive :css_changed
      refute_receive {:reload, :all}, 100
    end
  end

  describe "page_rendered/2" do
    test "does nothing when live reload is not running" do
      wait_for_process_cleanup(LiveReload)

      assert LiveReload.page_rendered("instance-1", Module1) == :ok
    end
  end

  describe "plan_batch/5" do
    # Page1 links to Page6 and Page7, Page4 to Page5: linked pages that do not sort first, so the
    # linked tier and the rest give different batches.
    @links %{
      Page1 => MapSet.new([Page6, Page7]),
      Page4 => MapSet.new([Page5])
    }

    @all_pages MapSet.new([Page1, Page2, Page3, Page4, Page5, Page6, Page7])

    test "the priority pages first, in the order requested" do
      open_pages = MapSet.new([Page1])

      assert LiveReload.plan_batch(@all_pages, @links, [Page6, Page5, Page6], open_pages, 2) ==
               [Page6, Page5]
    end

    test "a priority page no longer left to build is skipped" do
      remaining = MapSet.new([Page1, Page2])

      assert LiveReload.plan_batch(remaining, @links, [Page6], MapSet.new(), 2) == [Page1, Page2]
    end

    test "then every open page, whatever the batch size" do
      open_pages = MapSet.new([Page4, Page1, Page6])

      assert LiveReload.plan_batch(@all_pages, @links, [], open_pages, 1) ==
               [Page1, Page4, Page6]
    end

    test "then the pages the open ones link to, up to the batch size" do
      remaining = MapSet.new([Page2, Page3, Page5, Page6, Page7])
      open_pages = MapSet.new([Page1, Page4])

      assert LiveReload.plan_batch(remaining, @links, [], open_pages, 2) == [Page5, Page6]
    end

    test "a linked page no longer left to build is skipped" do
      remaining = MapSet.new([Page2, Page7])
      open_pages = MapSet.new([Page1])

      assert LiveReload.plan_batch(remaining, @links, [], open_pages, 2) == [Page7]
    end

    test "then the rest, up to the batch size, sorted" do
      remaining = MapSet.new([Page7, Page6, Page3])

      assert LiveReload.plan_batch(remaining, @links, [], MapSet.new([Page4]), 2) ==
               [Page3, Page6]
    end

    test "with no tab open, the rest" do
      remaining = MapSet.new([Page2, Page1])

      assert LiveReload.plan_batch(remaining, @links, [], MapSet.new(), 5) == [Page1, Page2]
    end
  end

  describe "replay_outcome/1" do
    test "does nothing when live reload is not running" do
      wait_for_process_cleanup(LiveReload)

      assert LiveReload.replay_outcome(self()) == :ok
    end
  end

  describe "start_link/1" do
    test "registers the process under its module name" do
      wait_for_process_cleanup(LiveReload)
      pid = start_supervised!({LiveReload, watch?: false})

      assert Process.whereis(LiveReload) == pid
    end
  end

  describe "watched_dirs/0" do
    test "single-app project" do
      result = LiveReload.watched_dirs()

      # Should return a list of string paths
      assert is_list(result)
      assert Enum.all?(result, &is_binary/1)

      # All paths should be absolute
      assert Enum.all?(result, fn path -> Path.type(path) == :absolute end)

      # Should contain the lib directory (standard in elixirc_paths)
      lib_path = Path.join([File.cwd!(), "lib"])
      assert lib_path in result
    end

    test "umbrella project" do
      umbrella_dir = Path.join(@fixtures_dir, "umbrella")
      app_a_dir = Path.join(umbrella_dir, "apps/app_a")
      app_b_dir = Path.join(umbrella_dir, "apps/app_b")

      result =
        Mix.Project.in_project(:umbrella_fixture, umbrella_dir, fn _module ->
          LiveReload.watched_dirs()
        end)

      # app_a doesn't set :elixirc_paths, so Mix's ["lib"] default applies
      assert Path.join(app_a_dir, "lib") in result

      assert Path.join(app_b_dir, "lib") in result
      assert Path.join(app_b_dir, "support") in result
    end
  end

  describe "watcher_opts/1" do
    test "with macOS" do
      result = LiveReload.watcher_opts({:unix, :darwin})

      assert is_list(result)

      assert Keyword.has_key?(result, :dirs)
      assert is_list(Keyword.get(result, :dirs))

      assert Keyword.has_key?(result, :latency)
      assert Keyword.get(result, :latency) == 0

      assert Keyword.has_key?(result, :no_defer)
      assert Keyword.get(result, :no_defer) == true
    end

    test "with other OS" do
      result = LiveReload.watcher_opts({:unix, :linux})

      assert is_list(result)

      assert Keyword.has_key?(result, :dirs)
      assert is_list(Keyword.get(result, :dirs))

      # Should not have macOS-specific options
      refute Keyword.has_key?(result, :latency)
      refute Keyword.has_key?(result, :no_defer)
    end
  end

  describe "watched_static_dir/0" do
    test "the priv/static dir in the project's dir" do
      assert LiveReload.watched_static_dir() == Path.join(File.cwd!(), "priv/static")
    end
  end

  describe "watcher_opts/1, the static dir" do
    setup do
      project_dir =
        Path.join([
          System.tmp_dir!(),
          "hologram_live_reload_test",
          to_string(System.unique_integer([:positive]))
        ])

      File.mkdir_p!(project_dir)
      on_exit(fn -> File.rm_rf!(project_dir) end)

      [project_dir: project_dir]
    end

    test "watched when it exists", %{project_dir: project_dir} do
      project_dir
      |> Path.join("priv/static")
      |> File.mkdir_p!()

      {static_dir, dirs} = static_dir_and_watched_dirs(project_dir)

      assert static_dir in dirs
    end

    test "left out when it doesn't exist", %{project_dir: project_dir} do
      {static_dir, dirs} = static_dir_and_watched_dirs(project_dir)

      refute static_dir in dirs
    end
  end

  describe "await_page/1" do
    test "returns at once when live reload is not running" do
      wait_for_process_cleanup(LiveReload)

      assert LiveReload.await_page(Page1) == :ok
    end
  end

  describe "live reload pass" do
    setup :set_mox_global

    setup do
      setup_asset_path_registry(AssetPathRegistryStub)
      setup_asset_manifest_cache(AssetManifestCacheStub)
      setup_chunk_registry(ChunkRegistryStub)
      setup_page_digest_registry(PageDigestRegistryStub)
      setup_page_module_resolver(PageModuleResolverStub)

      wait_for_process_cleanup(SubscriptionRegistry)
      start_supervised!(SubscriptionRegistry)

      start_supervised!({Task.Supervisor, name: LiveReload.TaskSupervisor})

      wait_for_process_cleanup(LiveReload)
      pid = start_supervised!({LiveReload, watch?: false})

      Phoenix.PubSub.subscribe(Hologram.PubSub, "hologram_live_reload")

      [pid: pid]
    end

    test "a debounced reload runs a pass with the file and the endpoint", %{pid: pid} do
      test_pid = self()

      expect(LiveReloadMock, :reload, fn file_path, endpoint, opts ->
        send(test_pid, {:reloaded, file_path, endpoint, Keyword.keys(opts)})
        :ok
      end)

      send(pid, {:debounced_reload, @file_path})

      assert_receive {:reloaded, @file_path, nil, option_keys}
      assert Enum.sort(option_keys) == [:bundles_built, :next_batch]

      wait_until(fn -> :sys.get_state(pid).pass == nil end)
    end

    test "a pass that compiled reports it", %{pid: pid} do
      expect(LiveReloadMock, :reload, fn _file_path, _endpoint, _opts -> :ok end)

      send(pid, {:debounced_reload, @file_path})

      assert_receive :compiled
    end

    test "a pass that a compile refused reports the error", %{pid: pid} do
      lines = [[%{tone: :banner, text: "** (Hologram.CompileError) boom"}]]

      expect(LiveReloadMock, :reload, fn _file_path, _endpoint, _opts -> {:error, lines} end)

      send(pid, {:debounced_reload, @file_path})

      assert_receive {:compilation_error, ^lines}
    end

    test "a stream attaching after a pass reported is sent the outcome", %{pid: pid} do
      lines = [[%{tone: :banner, text: "** (Hologram.CompileError) boom"}]]

      expect(LiveReloadMock, :reload, fn _file_path, _endpoint, _opts -> {:error, lines} end)

      send(pid, {:debounced_reload, @file_path})
      assert_receive {:compilation_error, ^lines}

      LiveReload.replay_outcome(self())

      assert_receive {:compilation_error, ^lines}
    end

    test "a stream attaching after a pass compiled past an error is sent that it compiled", %{
      pid: pid
    } do
      lines = [[%{tone: :banner, text: "** (Hologram.CompileError) boom"}]]

      expect(LiveReloadMock, :reload, 2, fn
        "first.ex", _endpoint, _opts -> {:error, lines}
        "second.ex", _endpoint, _opts -> :ok
      end)

      send(pid, {:debounced_reload, "first.ex"})
      assert_receive {:compilation_error, ^lines}

      send(pid, {:debounced_reload, "second.ex"})
      assert_receive :compiled

      LiveReload.replay_outcome(self())

      assert_receive :compiled
      refute_received {:compilation_error, _lines}
    end

    test "a stream attaching before any pass reported is sent nothing", %{pid: pid} do
      LiveReload.replay_outcome(self())

      # Handled once the state can be read back, so anything sent is in the mailbox by then.
      :sys.get_state(pid)

      refute_received :compiled
      refute_received {:compilation_error, _lines}
    end

    test "a stream attaching while a pass runs is sent nothing", %{pid: pid} do
      test_pid = self()
      lines = [[%{tone: :banner, text: "** (Hologram.CompileError) boom"}]]

      expect(LiveReloadMock, :reload, 2, fn
        "first.ex", _endpoint, _opts ->
          {:error, lines}

        "second.ex", _endpoint, _opts ->
          send(test_pid, {:second_started, self()})

          receive do
            :continue -> :ok
          end

          :ok
      end)

      send(pid, {:debounced_reload, "first.ex"})
      assert_receive {:compilation_error, ^lines}

      send(pid, {:debounced_reload, "second.ex"})
      assert_receive {:second_started, task_pid}

      LiveReload.replay_outcome(self())

      # Handled once the state can be read back, so anything sent is in the mailbox by then.
      :sys.get_state(pid)

      refute_received {:compilation_error, _lines}

      send(task_pid, :continue)
      assert_receive :compiled
    end

    test "asks for the pages open in tabs first", %{pid: pid} do
      :ok = SubscriptionRegistry.register_connection("instance-1", self())
      LiveReload.page_rendered("instance-1", Page2)

      test_pid = self()

      expect(LiveReloadMock, :reload, fn _file_path, _endpoint, opts ->
        next_batch = Keyword.fetch!(opts, :next_batch)
        remaining = MapSet.new([Page1, Page2, Page3])
        batch = next_batch.(remaining, %{})
        send(test_pid, {:batch, batch})
        :ok
      end)

      send(pid, {:debounced_reload, @file_path})

      assert_receive {:batch, [Page2]}
    end

    test "reloads the tabs on the pages a batch built, and no longer counts them pending", %{
      pid: pid
    } do
      test_pid = self()

      expect(LiveReloadMock, :reload, fn _file_path, _endpoint, opts ->
        next_batch = Keyword.fetch!(opts, :next_batch)
        bundles_built = Keyword.fetch!(opts, :bundles_built)

        remaining = MapSet.new([Page1, Page2, Page3])
        next_batch.(remaining, %{})
        bundles_built.([Page1, Page2])
        send(test_pid, :built)
        :ok
      end)

      send(pid, {:debounced_reload, @file_path})

      assert_receive {:reload, [Page1, Page2]}
      assert_receive :built
      assert :sys.get_state(pid).pending == MapSet.new([Page3])
    end

    test "reloads every tab when the chunk bundles were rebuilt", %{pid: pid} do
      expect(LiveReloadMock, :reload, fn _file_path, _endpoint, opts ->
        bundles_built = Keyword.fetch!(opts, :bundles_built)
        bundles_built.([:chunks, Page1])
        :ok
      end)

      send(pid, {:debounced_reload, @file_path})

      assert_receive {:reload, :all}
    end

    test "reloads every tab when the chunk bundles were rebuilt alone", %{pid: pid} do
      expect(LiveReloadMock, :reload, fn _file_path, _endpoint, opts ->
        bundles_built = Keyword.fetch!(opts, :bundles_built)
        bundles_built.([:chunks])
        :ok
      end)

      send(pid, {:debounced_reload, @file_path})

      assert_receive {:reload, :all}
    end

    test "reloads every tab when the runtime bundle was rebuilt", %{pid: pid} do
      expect(LiveReloadMock, :reload, fn _file_path, _endpoint, opts ->
        bundles_built = Keyword.fetch!(opts, :bundles_built)
        bundles_built.([:runtime, Page1])
        :ok
      end)

      send(pid, {:debounced_reload, @file_path})

      assert_receive {:reload, :all}
    end

    test "reloads the chunk registry with every batch", %{pid: pid} do
      test_pid = self()
      ets_table_name = ChunkRegistryStub.ets_table_name()

      # An entry the dump does not hold is gone once the registry is reloaded from it.
      stale_entry? = fn ->
        ets_table_name
        |> ETS.get_all()
        |> Map.has_key?(:stale_key)
      end

      expect(LiveReloadMock, :reload, fn _file_path, _endpoint, opts ->
        bundles_built = Keyword.fetch!(opts, :bundles_built)

        ETS.put(ets_table_name, :stale_key, :stale_value)
        bundles_built.([Page1])
        send(test_pid, {:stale_after_first_batch?, stale_entry?.()})

        ETS.put(ets_table_name, :stale_key, :stale_value)
        bundles_built.([Page2])
        send(test_pid, {:stale_after_second_batch?, stale_entry?.()})

        :ok
      end)

      send(pid, {:debounced_reload, @file_path})

      assert_receive {:stale_after_first_batch?, false}
      assert_receive {:stale_after_second_batch?, false}
    end

    test "a save during a pass stops it at its next batch and runs a pass of its own", %{
      pid: pid
    } do
      test_pid = self()

      expect(LiveReloadMock, :reload, 2, fn
        "first.ex", _endpoint, opts ->
          send(test_pid, {:first_started, self()})

          receive do
            :continue -> :ok
          end

          next_batch = Keyword.fetch!(opts, :next_batch)
          remaining = MapSet.new([Page1])
          batch = next_batch.(remaining, %{})
          send(test_pid, {:first_batch, batch})
          :ok

        "second.ex", _endpoint, _opts ->
          send(test_pid, :second_started)
          :ok
      end)

      send(pid, {:debounced_reload, "first.ex"})
      assert_receive {:first_started, task_pid}

      send(pid, {:debounced_reload, "second.ex"})

      # Handled once the state can be read back, so the save is recorded before the pass goes on.
      :sys.get_state(pid)
      send(task_pid, :continue)

      assert_receive {:first_batch, :stop}
      assert_receive :second_started
    end

    test "a superseded pass reports nothing, the pass that follows does", %{pid: pid} do
      test_pid = self()
      lines = [[%{tone: :banner, text: "** (Hologram.CompileError) boom"}]]

      expect(LiveReloadMock, :reload, 2, fn
        "first.ex", _endpoint, opts ->
          send(test_pid, {:first_started, self()})

          receive do
            :continue -> :ok
          end

          next_batch = Keyword.fetch!(opts, :next_batch)
          remaining = MapSet.new([Page1])
          batch = next_batch.(remaining, %{})
          send(test_pid, {:first_batch, batch})

          {:error, lines}

        "second.ex", _endpoint, _opts ->
          :ok
      end)

      send(pid, {:debounced_reload, "first.ex"})
      assert_receive {:first_started, task_pid}

      send(pid, {:debounced_reload, "second.ex"})

      # Handled once the state can be read back, so the save is recorded before the pass goes on.
      :sys.get_state(pid)
      send(task_pid, :continue)

      assert_receive {:first_batch, :stop}

      # The first pass ends before the second starts, so its outcome, had it been broadcast, would
      # be in the mailbox by the time the second one's arrives.
      assert_receive :compiled
      refute_received {:compilation_error, _lines}
    end

    test "a pass that crashes is logged, reports nothing, and the next save runs a pass", %{
      pid: pid
    } do
      test_pid = self()

      expect(LiveReloadMock, :reload, 2, fn
        "first.ex", _endpoint, _opts ->
          raise "expected test error"

        "second.ex", _endpoint, _opts ->
          send(test_pid, :second_started)
          :ok
      end)

      log =
        capture_log(fn ->
          send(pid, {:debounced_reload, "first.ex"})
          :sys.get_state(pid)
          wait_until(fn -> :sys.get_state(pid).pass == nil end)
        end)

      assert log =~
               ~r/Hologram: live reload pass failed: an exception was raised:\n\s+\*\* \(RuntimeError\) expected test error/

      refute_received :compiled
      refute_received {:compilation_error, _lines}

      send(pid, {:debounced_reload, "second.ex"})

      assert_receive :second_started
    end

    test "a request for a page that is not pending gets its bundle at once", %{pid: _pid} do
      assert LiveReload.await_page(Page1) == :ok
    end

    test "a request for a pending page waits for its batch, and pulls it to the front", %{
      pid: pid
    } do
      # The open page keeps the first batch to itself, so the other two stay pending.
      :ok = SubscriptionRegistry.register_connection("instance-1", self())
      LiveReload.page_rendered("instance-1", Page1)

      test_pid = self()

      expect(LiveReloadMock, :reload, fn _file_path, _endpoint, opts ->
        next_batch = Keyword.fetch!(opts, :next_batch)
        bundles_built = Keyword.fetch!(opts, :bundles_built)

        first_remaining = MapSet.new([Page1, Page2, Page3])
        first_batch = next_batch.(first_remaining, %{})
        bundles_built.(first_batch)

        send(test_pid, {:waiting, self()})

        receive do
          :continue -> :ok
        end

        second_remaining = MapSet.new([Page2, Page3])
        second_batch = next_batch.(second_remaining, %{})
        send(test_pid, {:second_batch, second_batch})
        bundles_built.(second_batch)

        :ok
      end)

      send(pid, {:debounced_reload, @file_path})
      assert_receive {:waiting, task_pid}

      request = Task.async(fn -> LiveReload.await_page(Page3) end)

      # The request is parked once the scheduler has handled it.
      wait_until(fn -> Map.has_key?(:sys.get_state(pid).waiters, Page3) end)
      assert Task.yield(request, 50) == nil

      send(task_pid, :continue)

      assert_receive {:second_batch, [Page3]}
      assert Task.await(request) == :ok
    end

    test "a request for a page a failed pass left pending starts a pass that builds it", %{
      pid: pid
    } do
      :ok = SubscriptionRegistry.register_connection("instance-1", self())
      LiveReload.page_rendered("instance-1", Page1)

      test_pid = self()

      expect(LiveReloadMock, :reload, 2, fn
        "first.ex", _endpoint, opts ->
          next_batch = Keyword.fetch!(opts, :next_batch)
          remaining = MapSet.new([Page1, Page2])
          next_batch.(remaining, %{})

          raise "expected test error"

        nil, _endpoint, opts ->
          next_batch = Keyword.fetch!(opts, :next_batch)
          bundles_built = Keyword.fetch!(opts, :bundles_built)

          remaining = MapSet.new([Page1, Page2])
          batch = next_batch.(remaining, %{})
          send(test_pid, {:requested_pass_batch, batch})
          bundles_built.(batch)

          :ok
      end)

      capture_log(fn ->
        send(pid, {:debounced_reload, "first.ex"})
        :sys.get_state(pid)
        wait_until(fn -> :sys.get_state(pid).pass == nil end)
      end)

      assert :sys.get_state(pid).pending == MapSet.new([Page1, Page2])

      assert LiveReload.await_page(Page2) == :ok
      assert_receive {:requested_pass_batch, [Page2]}
    end

    test "a waiting request is answered when the pass ends without its page", %{pid: pid} do
      :ok = SubscriptionRegistry.register_connection("instance-1", self())
      LiveReload.page_rendered("instance-1", Page1)

      test_pid = self()

      expect(LiveReloadMock, :reload, fn _file_path, _endpoint, opts ->
        next_batch = Keyword.fetch!(opts, :next_batch)
        remaining = MapSet.new([Page1, Page2])
        next_batch.(remaining, %{})

        send(test_pid, {:waiting, self()})

        receive do
          :continue -> :ok
        end

        :ok
      end)

      send(pid, {:debounced_reload, @file_path})
      assert_receive {:waiting, task_pid}

      request = Task.async(fn -> LiveReload.await_page(Page2) end)
      wait_until(fn -> Map.has_key?(:sys.get_state(pid).waiters, Page2) end)

      send(task_pid, :continue)

      assert Task.await(request) == :ok
      assert :sys.get_state(pid).waiters == %{}
    end

    test "a pass that outlives its scheduler does not report to the replacement", %{pid: pid} do
      test_pid = self()

      expect(LiveReloadMock, :reload, fn _file_path, _endpoint, opts ->
        send(test_pid, {:started, self()})

        receive do
          :continue -> :ok
        end

        next_batch = Keyword.fetch!(opts, :next_batch)
        remaining = MapSet.new([Page1])
        reason = catch_exit(next_batch.(remaining, %{}))
        send(test_pid, {:callback_exited, reason})

        :ok
      end)

      send(pid, {:debounced_reload, @file_path})
      assert_receive {:started, task_pid}

      # The scheduler goes away and a replacement takes its name, while the pass runs on.
      stop_supervised!(LiveReload)
      wait_for_process_cleanup(LiveReload)
      replacement_pid = start_supervised!({LiveReload, watch?: false})

      send(task_pid, :continue)

      assert_receive {:callback_exited, {:noproc, _call}}
      assert Process.alive?(replacement_pid)
      assert :sys.get_state(replacement_pid).pending == MapSet.new()
    end
  end
end
