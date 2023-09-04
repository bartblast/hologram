defmodule Mix.Tasks.Compile.HologramTest do
  use Hologram.Test.BasicCase, async: true
  import Mix.Tasks.Compile.Hologram

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.Reflection

  @root_path Reflection.root_path()
  @tmp_path "#{Reflection.tmp_path()}/#{__MODULE__}/run_1"

  setup do
    clean_dir(@tmp_path)
    :ok
  end

  defp test_build_artifacts do
    page_digest_dump_path = "#{@tmp_path}/build/page_digest.plt"
    assert File.exists?(page_digest_dump_path)

    call_graph_dump_path = "#{@tmp_path}/build/call_graph.bin"
    assert File.exists?(call_graph_dump_path)

    ir_plt_dump_path = "#{@tmp_path}/build/ir.plt"
    assert File.exists?(ir_plt_dump_path)

    module_digest_plt_dump_path = "#{@tmp_path}/build/module_digest.plt"
    assert File.exists?(module_digest_plt_dump_path)

    num_page_bundles =
      "#{@tmp_path}/bundle/hologram.page.????????????????????????????????.js"
      |> Path.wildcard()
      |> Enum.count()

    assert num_page_bundles > 1

    num_page_source_maps =
      "#{@tmp_path}/bundle/hologram.page.????????????????????????????????.js.map"
      |> Path.wildcard()
      |> Enum.count()

    assert num_page_source_maps == num_page_bundles

    num_runtime_bundles =
      "#{@tmp_path}/bundle/hologram.runtime.????????????????????????????????.js"
      |> Path.wildcard()
      |> Enum.count()

    assert num_runtime_bundles == 1

    num_runtime_source_maps =
      "#{@tmp_path}/bundle/hologram.runtime.????????????????????????????????.js.map"
      |> Path.wildcard()
      |> Enum.count()

    assert num_runtime_source_maps == 1

    page_digest_plt = PLT.start()
    PLT.load(page_digest_plt, page_digest_dump_path)
    page_digest_items = PLT.get_all(page_digest_plt)
    assert Enum.count(Map.keys(page_digest_items)) == num_page_bundles

    assert page_digest_items[Hologram.Test.Fixtures.Mix.Tasks.Compile.Module1] ==
             "992769ebf3ba16495f70bd8cd764555d"
  end

  # There are two tests in one test block here, because setup for the second test is expensive.
  test "run/1" do
    opts = [
      esbuild_path: "#{@root_path}/assets/node_modules/.bin/esbuild",
      js_source_dir: "#{@root_path}/assets/js",
      tmp_dir: "#{@tmp_path}/tmp",
      build_dir: "#{@tmp_path}/build",
      bundle_dir: "#{@tmp_path}/bundle"
    ]

    # Test case 1: when there are no previous build artifacts
    run(opts)
    test_build_artifacts()

    # Test case 2: when there are previous build artifacts
    run(opts)
    test_build_artifacts()
  end
end
