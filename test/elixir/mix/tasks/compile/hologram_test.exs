defmodule Mix.Tasks.Compile.HologramTest do
  use Hologram.Test.BasicCase, async: true
  import Mix.Tasks.Compile.Hologram

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.CallGraph
  alias Hologram.Reflection
  alias Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module1
  alias Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module2

  @compiler_lock_file_name Reflection.compiler_lock_file_name()

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
  @num_pages Enum.count(Reflection.list_pages())
  @static_dir Path.join(@test_dir, "static")
  @tmp_dir Path.join(@test_dir, "tmp")

  defp generate_old_bundle(name) do
    @static_dir
    |> Path.join("#{name}.js")
    |> File.write!(name)
  end

  defp test_build_artifacts do
    test_call_graph()
    test_dirs()
    test_js_deps()
    test_module_digest_plt()
    test_page_bundles()
    test_page_digest_plt()
    test_runtime_bundle()
  end

  defp test_call_graph do
    call_graph_dump_path = Path.join(@build_dir, Reflection.call_graph_dump_file_name())
    assert File.exists?(call_graph_dump_path)

    call_graph = CallGraph.start()
    CallGraph.load(call_graph, call_graph_dump_path)

    assert CallGraph.has_vertex?(call_graph, Module2)
  end

  defp test_dirs do
    assert File.exists?(@build_dir)
    assert File.exists?(@static_dir)
    assert File.exists?(@tmp_dir)
  end

  defp test_js_deps do
    assert @assets_dir
           |> Path.join("node_modules")
           |> File.exists?()
  end

  defp test_module_digest_plt do
    module_digest_plt_dump_path =
      Path.join(@build_dir, Reflection.module_digest_plt_dump_file_name())

    assert File.exists?(module_digest_plt_dump_path)

    module_digest_plt = PLT.start()
    PLT.load(module_digest_plt, module_digest_plt_dump_path)
    module_digest_items = PLT.get_all(module_digest_plt)

    assert map_size(module_digest_items) > 1_000

    assert is_integer(module_digest_items[Module1])
  end

  defp test_old_build_static_artifacts_cleanup do
    refute @static_dir
           |> Path.join("old_bundle_1.js")
           |> File.exists?()

    refute @static_dir
           |> Path.join("old_bundle_2.js")
           |> File.exists?()
  end

  defp test_page_bundles do
    num_page_bundles =
      @static_dir
      |> Path.join("page-????????????????????????????????.js")
      |> Path.wildcard()
      |> Enum.count()

    assert num_page_bundles == @num_pages

    num_page_source_maps =
      @static_dir
      |> Path.join("page-????????????????????????????????.js.map")
      |> Path.wildcard()
      |> Enum.count()

    assert num_page_source_maps == @num_pages
  end

  defp test_page_digest_plt do
    page_digest_plt_dump_path = Path.join(@build_dir, Reflection.page_digest_plt_dump_file_name())
    assert File.exists?(page_digest_plt_dump_path)

    page_digest_plt = PLT.start()
    PLT.load(page_digest_plt, page_digest_plt_dump_path)
    page_digest_items = PLT.get_all(page_digest_plt)

    assert map_size(page_digest_items) == @num_pages

    assert page_digest_items[Module1] =~ ~r/^[0-9a-f]{32}$/
  end

  defp test_runtime_bundle do
    num_runtime_bundles =
      @static_dir
      |> Path.join("runtime-????????????????????????????????.js")
      |> Path.wildcard()
      |> Enum.count()

    assert num_runtime_bundles == 1

    num_runtime_source_maps =
      @static_dir
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
    clean_dir(@test_dir)
    File.mkdir!(@assets_dir)

    lib_assets_dir = Path.join(Reflection.root_dir(), "assets")
    test_node_modules_path = Path.join(@assets_dir, "node_modules")

    opts = [
      assets_dir: @assets_dir,
      build_dir: @build_dir,
      esbuild_bin_path: Path.join([test_node_modules_path, ".bin", "esbuild"]),
      formatter_bin_path: Path.join([test_node_modules_path, ".bin", "biome"]),
      js_dir: Path.join(lib_assets_dir, "js"),
      static_dir: @static_dir,
      tmp_dir: @tmp_dir
    ]

    lib_package_json_path = Path.join([lib_assets_dir, "package.json"])
    test_package_json_path = Path.join(@assets_dir, "package.json")
    File.cp!(lib_package_json_path, test_package_json_path)

    [opts: opts]
  end

  test "run/1", %{opts: opts} do
    # Test case 1: when there are no previous build artifacts
    run(opts)
    test_build_artifacts()

    # Test case 2: when there are previous build artifacts
    generate_old_bundle("old_bundle_1")
    generate_old_bundle("old_bundle_2")
    run(opts)
    test_build_artifacts()
    test_old_build_static_artifacts_cleanup()
  end

  describe "compiler locking" do
    test "locking mechanism prevents concurrent compilation", %{opts: opts} do
      tasks =
        Enum.map(1..3, fn _i ->
          Task.async(fn ->
            run(opts)
            System.system_time(:millisecond)
          end)
        end)

      end_times =
        tasks
        |> Task.await_many(60_000)
        |> Enum.sort()

      [first_end, second_end, third_end] = end_times

      # Verify end times are spaced apart (indicating serialization)
      # Each compilation should end at different times (with reasonable gaps)
      # If they were running in parallel, end times would be very close
      # Expect at least 1000ms gap between compilations
      assert second_end - first_end > 1_000
      assert third_end - second_end > 1_000

      test_build_artifacts()
    end

    test "lock file is cleaned up after successful compilation", %{opts: opts} do
      lock_path = Path.join(opts[:build_dir], @compiler_lock_file_name)
      refute File.exists?(lock_path)

      run(opts)

      refute File.exists?(lock_path)
    end

    test "lock file is cleaned up after compilation error", %{opts: opts} do
      lock_path = Path.join(opts[:build_dir], @compiler_lock_file_name)
      refute File.exists?(lock_path)

      # Create a valid directory but with invalid package.json that will cause npm install to fail
      assets_dir = Path.join(@test_dir, "assets_with_invalid_package_json")
      File.mkdir_p!(assets_dir)

      # Create an invalid package.json that will cause npm install to fail
      invalid_package_json_path = Path.join(assets_dir, "package.json")
      File.write!(invalid_package_json_path, "{ invalid json content")

      opts = Keyword.put(opts, :assets_dir, assets_dir)

      assert_raise RuntimeError, "npm install command failed", fn ->
        run(opts)
      end

      refute File.exists?(lock_path)
    end

    test "lock directory is created if it doesn't exist", %{opts: opts} do
      File.rm_rf!(opts[:build_dir])
      refute File.exists?(opts[:build_dir])

      lock_path = Path.join(opts[:build_dir], @compiler_lock_file_name)

      run(opts)

      assert File.exists?(opts[:build_dir])

      refute File.exists?(lock_path)
    end

    test "stale lock file is automatically detected and removed", %{opts: opts} do
      File.mkdir_p!(opts[:build_dir])
      lock_path = Path.join(opts[:build_dir], @compiler_lock_file_name)

      # Create a stale lock file with a non-existent OS-level PID
      # Use a very high OS-level PID that's unlikely to exist
      # Default max PIDs are:
      # Linux = 32,768, see: https://stackoverflow.com/a/6294196/13040586
      # macOs = 99,998, see: https://apple.stackexchange.com/a/260798
      # Windows = 4,294,967,295, see: https://learn.microsoft.com/en-us/answers/questions/70930/maximum-value-of-process-id
      stale_os_pid = 32_768
      File.write!(lock_path, "#{stale_os_pid}")

      assert File.exists?(lock_path)

      run(opts)

      # Lock should be cleaned up after successful compilation
      refute File.exists?(lock_path)
    end

    test "valid lock file with running OS-level process is respected", %{opts: opts} do
      File.mkdir_p!(opts[:build_dir])
      lock_path = Path.join(opts[:build_dir], @compiler_lock_file_name)

      # Create a lock file with the current process PID (which is definitely running)
      current_os_pid = System.pid()
      File.write!(lock_path, "#{current_os_pid}")

      assert File.exists?(lock_path)

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
      File.rm!(lock_path)

      # The task should eventually complete after waiting for the lock
      duration = Task.await(task, :infinity)

      # Should have waited at least 2 seconds (our sleep above)
      assert duration >= 2_000

      # Lock should be cleaned up after successful compilation
      refute File.exists?(lock_path)
    end

    test "lock file with invalid OS-level PID format is removed", %{opts: opts} do
      File.mkdir_p!(opts[:build_dir])
      lock_path = Path.join(opts[:build_dir], @compiler_lock_file_name)

      # Create a lock file with invalid OS-level PID format
      File.write!(lock_path, "invalid_pid_format")

      assert File.exists?(lock_path)

      run(opts)

      # Lock should be cleaned up after successful compilation
      refute File.exists?(lock_path)
    end

    test "unreadable lock file is removed", %{opts: opts} do
      File.mkdir_p!(opts[:build_dir])
      lock_path = Path.join(opts[:build_dir], @compiler_lock_file_name)

      # Create a lock file and make it unreadable (if supported by OS)
      File.write!(lock_path, "12345")
      File.chmod!(lock_path, 0o000)

      assert File.exists?(lock_path)

      run(opts)

      # Lock should be cleaned up after successful compilation
      refute File.exists?(lock_path)
    end

    test "lock file contains current OS-level process PID during compilation", %{opts: opts} do
      File.mkdir_p!(opts[:build_dir])
      lock_path = Path.join(opts[:build_dir], @compiler_lock_file_name)

      # Start compilation in a background task
      compilation_task =
        Task.async(fn ->
          run(opts)
        end)

      # Wait for lock file to appear and read its content
      lock_content = wait_for_lock_file(lock_path, 5_000)

      # Verify the OS-level PID format
      assert is_binary(lock_content)
      assert {parsed_os_pid, ""} = Integer.parse(lock_content)
      assert parsed_os_pid > 0

      # The OS-level PID should correspond to a running OS process
      assert System.cmd("ps", ["-p", lock_content]) |> elem(1) == 0

      # Clean up: kill the background compilation task
      Task.shutdown(compilation_task, :brutal_kill)
    end
  end

  describe "edge cases and error conditions" do
    @tag :skip_on_windows
    test "handles file system errors gracefully", %{opts: opts} do
      build_dir = Path.join([Reflection.tmp_dir(), "readonly_build_dir"])
      File.mkdir_p!(build_dir)

      # Make build dir read-only
      File.chmod!(build_dir, 0o444)

      opts = Keyword.put(opts, :build_dir, build_dir)

      # Should raise a permission error when trying to create lock file in read-only directory
      assert_raise RuntimeError, ~r/failed to acquire compiler lock.*eacces/i, fn ->
        run(opts)
      end

      # Reset permissions for cleanup
      File.chmod!(build_dir, 0o755)
      File.rm_rf!(build_dir)
    end
  end
end
