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

      # Create invalid opts that will cause compilation to fail early
      invalid_opts = Keyword.put(opts, :assets_dir, "/nonexistent/assets/dir")

      assert_raise RuntimeError, "npm install command failed", fn ->
        run(invalid_opts)
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
  end
end
