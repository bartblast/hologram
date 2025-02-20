defmodule Mix.Tasks.Compile.HologramTest do
  use Hologram.Test.BasicCase, async: true
  import Mix.Tasks.Compile.Hologram

  alias Hologram.Commons.PLT
  alias Hologram.Reflection
  alias Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module1
  alias Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module2

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
    test_dirs()
    test_js_deps()
    test_module_beam_path_plt()
    test_page_bundles()
    test_page_digest_plt()
    test_runtime_bundle()
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

  defp test_module_beam_path_plt do
    module_beam_path_plt_dump_path =
      Path.join(@build_dir, Reflection.module_beam_path_plt_dump_file_name())

    assert File.exists?(module_beam_path_plt_dump_path)

    module_beam_path_plt = PLT.start()
    PLT.load(module_beam_path_plt, module_beam_path_plt_dump_path)
    assert PLT.get!(module_beam_path_plt, Module2) == :code.which(Module2)
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
    page_digest_dump_path = Path.join(@build_dir, Reflection.page_digest_plt_dump_file_name())
    assert File.exists?(page_digest_dump_path)

    page_digest_plt = PLT.start()
    PLT.load(page_digest_plt, page_digest_dump_path)
    page_digest_items = PLT.get_all(page_digest_plt)

    num_page_bundles =
      page_digest_items
      |> Map.keys()
      |> Enum.count()

    assert num_page_bundles == @num_pages

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
end
