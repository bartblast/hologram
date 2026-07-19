defmodule Mix.Tasks.Compile.HologramTest do
  use Hologram.Test.BasicCase, async: false
  import Mix.Tasks.Compile.Hologram

  alias Hologram.Commons.FileUtils
  alias Hologram.Commons.PLT
  alias Hologram.Commons.SystemUtils
  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Reflection
  alias Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module1
  alias Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module2

  @lib_assets_dir Path.join(Reflection.root_dir(), "assets")
  @lib_package_json_path Path.join(@lib_assets_dir, "package.json")

  @test_dir Path.join([
              Reflection.tmp_dir(),
              "tests",
              "mix",
              "tasks",
              "compile.hologram",
              "run_1"
            ])

  @assets_dir Path.join(@test_dir, "assets")
  @build_dir Path.join(@test_dir, "build")
  @static_dir Path.join(@test_dir, "static")
  @tmp_dir Path.join(@test_dir, "tmp")

  @compiler_lock_file_name Reflection.compiler_lock_file_name()
  @lock_path Path.join(@build_dir, @compiler_lock_file_name)

  @num_pages Enum.count(Reflection.list_pages())

  defp count_plt_processes do
    Enum.count(Process.list(), fn pid ->
      case Process.info(pid, :dictionary) do
        {:dictionary, dict} -> Keyword.get(dict, :"$initial_call") == {PLT, :init, 1}
        nil -> false
      end
    end)
  end

  defp generate_old_bundle(name, opts) do
    opts[:static_dir]
    |> Path.join("#{name}.js")
    |> File.write!(name)
  end

  # Telemetry handler that tracks how many compilations are inside the critical
  # section at once, recording the running maximum. Public because telemetry
  # warns when a handler is captured as a local or anonymous function.
  @spec handle_compiler_telemetry(
          :telemetry.event_name(),
          :telemetry.event_measurements(),
          :telemetry.event_metadata(),
          Agent.agent()
        ) :: :ok
  def handle_compiler_telemetry(event_name, measurements, metadata, tracker)

  def handle_compiler_telemetry([:hologram, :compiler, :start], _measurements, _metadata, tracker) do
    Agent.update(tracker, fn %{current: current, max: max_seen} ->
      new_current = current + 1
      %{current: new_current, max: max(max_seen, new_current)}
    end)
  end

  def handle_compiler_telemetry([:hologram, :compiler, :stop], _measurements, _metadata, tracker) do
    Agent.update(tracker, fn state -> %{state | current: state.current - 1} end)
  end

  defp setup_empty_assets_and_build_dirs(opts) do
    assets_dir = setup_empty_assets_dir()
    build_dir = setup_empty_build_dir()

    opts
    |> Keyword.put(:assets_dir, assets_dir)
    |> Keyword.put(:build_dir, build_dir)
  end

  defp setup_empty_assets_dir do
    assets_dir = Path.join(@test_dir, "assets_empty")
    clean_dir(assets_dir)

    test_package_json_path = Path.join(assets_dir, "package.json")
    FileUtils.cp_p!(@lib_package_json_path, test_package_json_path)

    assets_dir
  end

  defp setup_empty_build_dir do
    build_dir = Path.join(@test_dir, "build_empty")
    clean_dir(build_dir)

    build_dir
  end

  defp test_build_artifacts(opts) do
    test_call_graph(opts)
    test_dirs(opts)
    test_js_deps(opts)
    test_module_digest_plt(opts)
    test_page_bundles(opts)
    test_page_digest_plt(opts)
    test_runtime_bundle(opts)
  end

  defp test_call_graph(opts) do
    call_graph_dump_path = Path.join(opts[:build_dir], Reflection.call_graph_dump_file_name())
    assert File.exists?(call_graph_dump_path)

    call_graph = CallGraph.start()
    CallGraph.load(call_graph, call_graph_dump_path)

    assert CallGraph.has_vertex?(call_graph, Module2)

    # Erlang MFA edges are added during compilation
    assert CallGraph.has_edge?(call_graph, {:binary, :match, 2}, {:binary, :match, 3})

    # Dynamic dispatch edges are added during compilation
    assert CallGraph.has_edge?(call_graph, {Date, :new, 4}, {Calendar.ISO, :valid_date?, 3})
  end

  defp test_dirs(opts) do
    assert File.exists?(opts[:build_dir])
    assert File.exists?(opts[:static_dir])
    assert File.exists?(opts[:tmp_dir])
  end

  defp test_js_deps(opts) do
    assert opts[:assets_dir]
           |> Path.join("node_modules")
           |> File.exists?()
  end

  defp test_module_digest_plt(opts) do
    module_digest_plt_dump_path =
      Path.join(opts[:build_dir], Reflection.module_digest_plt_dump_file_name())

    assert File.exists?(module_digest_plt_dump_path)

    module_digest_plt = PLT.start()
    PLT.load(module_digest_plt, module_digest_plt_dump_path)
    module_digest_items = PLT.get_all(module_digest_plt)

    assert map_size(module_digest_items) > 1_000

    assert is_integer(module_digest_items[Module1])
  end

  defp test_old_build_static_artifacts_cleanup(opts) do
    refute opts[:static_dir]
           |> Path.join("old_bundle_1.js")
           |> File.exists?()

    refute opts[:static_dir]
           |> Path.join("old_bundle_2.js")
           |> File.exists?()
  end

  defp test_page_bundles(opts) do
    num_page_bundles =
      opts[:static_dir]
      |> Path.join("page-????????????????????????????????.js")
      |> Path.wildcard()
      |> Enum.count()

    assert num_page_bundles == @num_pages

    num_page_source_maps =
      opts[:static_dir]
      |> Path.join("page-????????????????????????????????.js.map")
      |> Path.wildcard()
      |> Enum.count()

    assert num_page_source_maps == @num_pages
  end

  defp test_page_digest_plt(opts) do
    page_digest_plt_dump_path =
      Path.join(opts[:build_dir], Reflection.page_digest_plt_dump_file_name())

    assert File.exists?(page_digest_plt_dump_path)

    page_digest_plt = PLT.start()
    PLT.load(page_digest_plt, page_digest_plt_dump_path)
    page_digest_items = PLT.get_all(page_digest_plt)

    assert map_size(page_digest_items) == @num_pages

    assert page_digest_items[Module1] =~ ~r/^[0-9a-f]{32}$/
  end

  defp test_runtime_bundle(opts) do
    num_runtime_bundles =
      opts[:static_dir]
      |> Path.join("runtime-????????????????????????????????.js")
      |> Path.wildcard()
      |> Enum.count()

    assert num_runtime_bundles == 1

    num_runtime_source_maps =
      opts[:static_dir]
      |> Path.join("runtime-????????????????????????????????.js.map")
      |> Path.wildcard()
      |> Enum.count()

    assert num_runtime_source_maps == 1
  end

  # Helper function to wait for lock file to appear and return its content
  defp wait_for_lock_file(lock_path, timeout_ms, end_time \\ nil) do
    end_time = end_time || System.system_time(:millisecond) + timeout_ms

    if System.system_time(:millisecond) > end_time do
      flunk("Lock file did not appear within timeout")
    end

    if File.exists?(lock_path) do
      case File.read(lock_path) do
        {:ok, content} ->
          content

        {:error, _reason} ->
          Process.sleep(10)
          wait_for_lock_file(lock_path, timeout_ms, end_time)
      end
    else
      Process.sleep(10)
      wait_for_lock_file(lock_path, timeout_ms, end_time)
    end
  end

  setup_all do
    original_hologram_start_flag = System.get_env("HOLOGRAM_START")
    System.put_env("HOLOGRAM_START", "1")

    on_exit(fn ->
      if original_hologram_start_flag do
        System.put_env("HOLOGRAM_START", original_hologram_start_flag)
      else
        System.delete_env("HOLOGRAM_START")
      end
    end)

    clean_dir(@test_dir)
    File.mkdir!(@assets_dir)
    File.mkdir!(@build_dir)

    test_node_modules_path = Path.join(@assets_dir, "node_modules")

    opts = [
      assets_dir: @assets_dir,
      build_dir: @build_dir,
      esbuild_bin_path: Path.join([test_node_modules_path, ".bin", "esbuild"]),
      js_dir: Path.join(@lib_assets_dir, "js"),
      node_modules_path: test_node_modules_path,
      static_dir: @static_dir,
      tmp_dir: @tmp_dir
    ]

    test_package_json_path = Path.join(@assets_dir, "package.json")
    FileUtils.cp_p!(@lib_package_json_path, test_package_json_path)

    Compiler.install_js_deps(@assets_dir, @build_dir)

    [opts: opts]
  end

  setup do
    File.rm(@lock_path)

    clean_dir(@static_dir)
    clean_dir(@tmp_dir)
  end

  describe "compiler skipping" do
    setup do
      on_exit(fn -> System.put_env("HOLOGRAM_START", "1") end)
    end

    test "skips compilation when HOLOGRAM_START env var is not set", %{opts: opts} do
      System.delete_env("HOLOGRAM_START")

      assert run(opts) == :noop
    end

    test "skips compilation for language server builds", %{opts: opts} do
      ls_opts = Keyword.put(opts, :build_dir, Path.join(opts[:build_dir], ".expert"))

      assert run(ls_opts) == :noop
    end

    test "runs compilation when HOLOGRAM_START env var is set to 1", %{opts: opts} do
      System.put_env("HOLOGRAM_START", "1")

      assert run(opts) == :ok
    end

    test "validates the data model even when compilation is skipped", %{opts: opts} do
      System.delete_env("HOLOGRAM_START")

      defmodule InvalidEntityFixture do
        use Hologram.Entity

        relationship :owner, NonExistent.Module
      end

      # Register a fake loaded OTP app whose spec lists the invalid entity type module,
      # so that data model discovery picks it up.
      fixture_app = :hologram_invalid_entity_fixture_app
      :ok = :application.load({:application, fixture_app, [modules: [InvalidEntityFixture]]})
      on_exit(fn -> :application.unload(fixture_app) end)

      expected_msg =
        "invalid data model:\n  * relationship :owner in Mix.Tasks.Compile.HologramTest.InvalidEntityFixture targets NonExistent.Module, which is not an entity type module"

      assert_error Hologram.CompileError, expected_msg, fn ->
        run(opts)
      end
    end

    test "fails the build on mapping errors even when compilation is skipped", %{opts: opts} do
      System.delete_env("HOLOGRAM_START")

      defmodule InvalidMappingEntityFixture do
        use Hologram.Entity

        attribute :owner_id, :string

        relationship :owner, Hologram.Test.Fixtures.Entity.Module1
      end

      # Register a fake loaded OTP app whose spec lists the entity type module with the
      # colliding declarations, so that data model discovery picks it up.
      fixture_app = :hologram_invalid_mapping_entity_fixture_app

      :ok =
        :application.load({:application, fixture_app, [modules: [InvalidMappingEntityFixture]]})

      on_exit(fn -> :application.unload(fixture_app) end)

      expected_msg = """
      colliding column names in Mix.Tasks.Compile.HologramTest.InvalidMappingEntityFixture - rename the declarations so that every derived column name is unique:
        * column "owner_id" is derived from attribute :owner_id, relationship :owner\
      """

      assert_error Hologram.CompileError, expected_msg, fn ->
        run(opts)
      end
    end
  end

  test "compilation artifacts", %{opts: initial_opts} do
    opts = setup_empty_assets_and_build_dirs(initial_opts)

    # Test case 1: when there are no previous build artifacts
    run(opts)
    test_build_artifacts(opts)

    # Test case 2: when there are previous build artifacts
    generate_old_bundle("old_bundle_1", opts)
    generate_old_bundle("old_bundle_2", opts)
    run(opts)
    test_build_artifacts(opts)
    test_old_build_static_artifacts_cleanup(opts)
  end

  test "stops the processes it spawns once compilation finishes", %{opts: initial_opts} do
    opts = setup_empty_assets_and_build_dirs(initial_opts)

    before_count = count_plt_processes()
    run(opts)
    after_count = count_plt_processes()

    assert after_count == before_count
  end

  describe "compiler locking" do
    test "locking mechanism prevents concurrent compilation", %{opts: opts} do
      # The lock guards the actual compilation work, which emits
      # [:hologram, :compiler, :start] when it enters the critical section and
      # [:hologram, :compiler, :stop] when it leaves. By tracking how many
      # compilations are inside the critical section at any moment, we verify the
      # lock's core guarantee directly: at no point do two compilations overlap.
      # If the lock failed, two concurrent invocations would be inside the section
      # together and the observed maximum concurrency would be 2.
      {:ok, tracker} = Agent.start_link(fn -> %{current: 0, max: 0} end)

      handler_id = "compiler-lock-test"

      events = [
        [:hologram, :compiler, :start],
        [:hologram, :compiler, :stop]
      ]

      :telemetry.attach_many(handler_id, events, &__MODULE__.handle_compiler_telemetry/4, tracker)
      on_exit(fn -> :telemetry.detach(handler_id) end)

      1..3
      |> Enum.map(fn _i -> Task.async(fn -> run(opts) end) end)
      |> Task.await_many(:infinity)

      assert Agent.get(tracker, & &1.max) == 1
    end

    test "lock file is cleaned up after successful compilation", %{opts: opts} do
      refute File.exists?(@lock_path)

      run(opts)

      refute File.exists?(@lock_path)
    end

    test "lock file is cleaned up after compilation error", %{opts: initial_opts} do
      opts = setup_empty_assets_and_build_dirs(initial_opts)

      # Create an invalid package.json that will cause npm install to fail
      package_json_path = Path.join(opts[:assets_dir], "package.json")
      File.write!(package_json_path, "{ invalid json content")

      refute File.exists?(@lock_path)

      assert_raise RuntimeError, "npm install command failed", fn ->
        run(opts)
      end

      refute File.exists?(@lock_path)
    end

    test "lock dir (which is the build dir) is created if it doesn't exist", %{opts: initial_opts} do
      opts = setup_empty_assets_and_build_dirs(initial_opts)

      build_dir = opts[:build_dir]
      lock_path = Path.join(build_dir, @compiler_lock_file_name)

      FileUtils.rm_rf_with_retries!(build_dir, 5, 10)

      refute File.exists?(build_dir)

      run(opts)

      assert File.exists?(build_dir)

      refute File.exists?(lock_path)
    end

    test "stale lock file is automatically detected and removed", %{opts: opts} do
      # Create a stale lock file with a non-existent OS-level PID
      # Use a very high OS-level PID that's unlikely to exist
      # Default max PIDs are:
      # Linux = 32,768, see: https://stackoverflow.com/a/6294196/13040586
      # macOs = 99,998, see: https://apple.stackexchange.com/a/260798
      # Windows = 4,294,967,295, see: https://learn.microsoft.com/en-us/answers/questions/70930/maximum-value-of-process-id
      stale_os_pid = 32_768
      FileUtils.write_p!(@lock_path, "#{stale_os_pid}")

      assert File.exists?(@lock_path)

      run(opts)

      # Lock should be cleaned up after successful compilation
      refute File.exists?(@lock_path)
    end

    test "valid lock file with running OS-level process is respected", %{opts: opts} do
      # Create a lock file with the current process PID (which is definitely running)
      current_os_pid = System.pid()
      FileUtils.write_p!(@lock_path, "#{current_os_pid}")

      assert File.exists?(@lock_path)

      # Start a task that will try to run compilation
      task =
        Task.async(fn ->
          start_time = System.system_time(:millisecond)
          run(opts)
          end_time = System.system_time(:millisecond)
          end_time - start_time
        end)

      # Remove the lock file after a short delay to simulate the "running" process finishing
      Process.sleep(2_000)
      File.rm!(@lock_path)

      # The task should eventually complete after waiting for the lock
      duration = Task.await(task, :infinity)

      # Should have waited at least 2 seconds (our sleep above)
      assert duration >= 2_000

      # Lock should be cleaned up after successful compilation
      refute File.exists?(@lock_path)
    end

    test "lock file with invalid OS-level PID format is removed", %{opts: opts} do
      # Create a lock file with invalid OS-level PID format
      FileUtils.write_p!(@lock_path, "invalid_pid_format")

      assert File.exists?(@lock_path)

      run(opts)

      # Lock should be cleaned up after successful compilation
      refute File.exists?(@lock_path)
    end

    test "lock file contains current OS-level process PID during compilation", %{opts: opts} do
      # Start compilation in a background task
      compilation_task =
        Task.async(fn ->
          run(opts)
        end)

      # Wait for lock file to appear and read its content
      lock_content = wait_for_lock_file(@lock_path, 5_000)

      # Verify the OS-level PID format
      assert is_binary(lock_content)
      assert {parsed_os_pid, ""} = Integer.parse(lock_content)
      assert parsed_os_pid > 0

      # The OS-level PID should correspond to a running OS process
      assert SystemUtils.os_process_alive?(parsed_os_pid)

      # Clean up: kill the background compilation task
      Task.shutdown(compilation_task, :brutal_kill)
    end
  end
end
