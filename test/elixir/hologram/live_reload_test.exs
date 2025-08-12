# Note: These tests focus on the GenServer message handling logic and do not
# test the actual Phoenix.CodeReloader or Mix.Tasks.Compile.Hologram integration,
# as those require the full Hologram/Phoenix application infrastructure.
# Some tests suppress Logger output to avoid expected error messages from
# Phoenix.CodeReloader when testing with nil endpoints.

defmodule Hologram.LiveReloadTest do
  use Hologram.Test.BasicCase, async: false
  alias Hologram.LiveReload
  require Logger

  @debounce_delay LiveReload.debounce_delay()
  @file_path Path.join([@fixtures_dir, "live_reload", "module_1.ex"])

  defp suppress_phoenix_errors(fun) do
    original_level = Logger.level()
    Logger.configure(level: :emergency)

    try do
      fun.()
    after
      Logger.configure(level: original_level)
    end
  end

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

    test "ignores :renamed file events", %{state: state} do
      result = LiveReload.handle_info({:file_event, self(), {@file_path, [:renamed]}}, state)
      assert result == {:noreply, state}
    end

    test "starts debounce timer for file changes", %{state: state} do
      result = LiveReload.handle_info({:file_event, self(), {@file_path, [:modified]}}, state)

      assert {:noreply, new_state} = result
      assert is_reference(new_state.timer_ref)
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

    test "debounce timer sends debounced_reload message after delay", %{state: state} do
      LiveReload.handle_info({:file_event, self(), {@file_path, [:modified]}}, state)

      assert_receive {:debounced_reload, @file_path}, @debounce_delay + 100
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

  # This tests the private logic indirectly by checking what file types trigger reload attempts
  describe "file path processing" do
    setup do
      [state: %{endpoint: nil, timer_ref: make_ref()}]
    end

    test "handles .ex files", %{state: state} do
      # The error being raised proves that .ex files trigger compilation attempts,
      # but fail due to missing Phoenix setup (nil endpoint)
      suppress_phoenix_errors(fn ->
        catch_exit(LiveReload.handle_info({:debounced_reload, @file_path}, state))
      end)
    end

    test "handles .holo files with corresponding .ex files", %{state: state} do
      holo_file = Path.join([@fixtures_dir, "live_reload", "module_1.holo"])

      # The error being raised proves that .holo files with corresponding .ex files
      # trigger compilation attempts, but fail due to missing Phoenix setup (nil endpoint)
      suppress_phoenix_errors(fn ->
        catch_exit(LiveReload.handle_info({:debounced_reload, holo_file}, state))
      end)
    end

    test "ignores .holo files without corresponding .ex files", %{state: state} do
      orphaned_holo_file = Path.join([@fixtures_dir, "live_reload", "orphaned.holo"])

      result = LiveReload.handle_info({:debounced_reload, orphaned_holo_file}, state)

      assert {:noreply, new_state} = result
      assert new_state.timer_ref == nil
    end

    test "ignores files with extensions other than .ex or .holo", %{state: state} do
      ignored_files = [
        Path.join([@fixtures_dir, "live_reload", "file.css"]),
        Path.join([@fixtures_dir, "live_reload", "file.json"]),
        Path.join([@fixtures_dir, "live_reload", "file.md"]),
        Path.join([@fixtures_dir, "live_reload", "file.text"])
      ]

      for file_path <- ignored_files do
        result = LiveReload.handle_info({:debounced_reload, file_path}, state)
        assert {:noreply, new_state} = result
        assert new_state.timer_ref == nil
      end
    end
  end
end
