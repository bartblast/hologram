# Note: These tests focus on the GenServer message handling logic and do not
# test the actual Phoenix.CodeReloader or Mix.Tasks.Compile.Hologram integration,
# as those require the full Hologram/Phoenix application infrastructure.
# Some tests suppress Logger output to avoid expected error messages from
# Phoenix.CodeReloader when testing with nil endpoints.

defmodule Hologram.LiveReloadTest do
  use Hologram.Test.BasicCase, async: false
  require Logger
  alias Hologram.LiveReload

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
      [state: %{endpoint: nil, timer_ref: nil}]
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

  test "watched_dirs/0" do
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

  describe "debounced reload handling" do
    setup do
      [state: %{endpoint: :dummy_endpoint, timer_ref: make_ref()}]
    end

    test "debounced_reload always triggers reload attempt", %{state: state} do
      import Mox, only: [expect: 3]

      # Mock the reload function to be called (but can raise an error to simulate real behavior)
      expect(LiveReloadMock, :reload, fn @file_path, :dummy_endpoint ->
        # Simulate Phoenix.CodeReloader failure
        raise "expected test error"
      end)

      assert_raise RuntimeError, "expected test error", fn ->
        LiveReload.handle_info({:debounced_reload, @file_path}, state)
      end
    end

    test "debounced_reload clears timer_ref", %{state: state} do
      import Mox, only: [expect: 3]

      timer_ref = make_ref()
      state_with_timer = %{state | timer_ref: timer_ref}

      expect(LiveReloadMock, :reload, fn @file_path, :dummy_endpoint -> :ok end)

      result = LiveReload.handle_info({:debounced_reload, @file_path}, state_with_timer)

      assert {:noreply, new_state} = result
      assert new_state.timer_ref == nil
    end
  end
end
