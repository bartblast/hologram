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

  alias Hologram.LiveReload
  alias Hologram.Realtime.SubscriptionRegistry

  use_module_stub :asset_manifest_cache
  use_module_stub :asset_path_registry
  use_module_stub :page_digest_registry
  use_module_stub :page_module_resolver

  @debounce_delay LiveReload.debounce_delay()
  @file_path Path.join([@fixtures_dir, "live_reload", "module_1.ex"])

  setup do
    wait_for_process_cleanup(Hologram.PubSub)
    start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

    :ok
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

    test "forgets a tab with no SSE connection" do
      :ok = SubscriptionRegistry.register_connection("instance-1", self())

      LiveReload.page_rendered("instance-1", Module1)
      LiveReload.page_rendered("instance-2", Module2)

      assert LiveReload.open_pages() == %{"instance-1" => Module1}
      assert :sys.get_state(LiveReload).open_pages == %{"instance-1" => Module1}
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

  describe "live reload pass" do
    setup :set_mox_global

    setup do
      setup_asset_path_registry(AssetPathRegistryStub)
      setup_asset_manifest_cache(AssetManifestCacheStub)
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

    test "reloads every tab when the runtime bundle was rebuilt", %{pid: pid} do
      expect(LiveReloadMock, :reload, fn _file_path, _endpoint, opts ->
        bundles_built = Keyword.fetch!(opts, :bundles_built)
        bundles_built.([:runtime, Page1])
        :ok
      end)

      send(pid, {:debounced_reload, @file_path})

      assert_receive {:reload, :all}
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

    test "a pass that fails is logged, and the next save runs a pass", %{pid: pid} do
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

      assert log =~ "Hologram: live reload pass failed"

      send(pid, {:debounced_reload, "second.ex"})

      assert_receive :second_started
    end
  end
end
