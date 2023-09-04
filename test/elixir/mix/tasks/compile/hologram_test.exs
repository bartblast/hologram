defmodule Mix.Tasks.Compile.HologramTest do
  use Hologram.Test.BasicCase, async: true
  import Mix.Tasks.Compile.Hologram

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.IR
  alias Hologram.Compiler.Reflection
  alias Hologram.Test.Fixtures.Mix.Tasks.Compile.Module1
  alias Hologram.Test.Fixtures.Mix.Tasks.Compile.Module2

  @root_path Reflection.root_path()
  @tmp_path "#{Reflection.tmp_path()}/#{__MODULE__}/run_1"

  setup do
    clean_dir(@tmp_path)
    :ok
  end

  defp test_build_artifacts do
    num_page_bundles = test_page_bundles()
    test_runtime_bundle()

    test_module_digest_plt()
    test_ir_plt()
    test_call_graph()
    test_page_digest_plt(num_page_bundles)
  end

  defp test_call_graph do
    call_graph_dump_path = "#{@tmp_path}/build/call_graph.bin"
    assert File.exists?(call_graph_dump_path)

    call_graph = CallGraph.start()
    CallGraph.load(call_graph, call_graph_dump_path)

    assert CallGraph.inbound_remote_edges(call_graph, Module2) == [
             %Graph.Edge{v1: {Module1, :__hologram_layout_module__, 0}, v2: Module2}
           ]
  end

  defp test_ir_plt do
    ir_plt_dump_path = "#{@tmp_path}/build/ir.plt"
    assert File.exists?(ir_plt_dump_path)

    ir_plt = PLT.start()
    PLT.load(ir_plt, ir_plt_dump_path)
    assert %IR.ModuleDefinition{} = PLT.get!(ir_plt, Module2)
  end

  defp test_module_digest_plt do
    module_digest_plt_dump_path = "#{@tmp_path}/build/module_digest.plt"
    assert File.exists?(module_digest_plt_dump_path)

    module_digest_plt = PLT.start()
    PLT.load(module_digest_plt, module_digest_plt_dump_path)

    assert PLT.get!(module_digest_plt, Module2) ==
             <<192, 132, 144, 80, 65, 123, 26, 73, 18, 78, 113, 30, 217, 117, 223, 122, 185, 70,
               94, 250, 169, 95, 98, 128, 111, 218, 140, 29, 241, 247, 3, 69>>
  end

  defp test_page_bundles do
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

    num_page_bundles
  end

  defp test_page_digest_plt(num_page_bundles) do
    page_digest_dump_path = "#{@tmp_path}/build/page_digest.plt"
    assert File.exists?(page_digest_dump_path)

    page_digest_plt = PLT.start()
    PLT.load(page_digest_plt, page_digest_dump_path)
    page_digest_items = PLT.get_all(page_digest_plt)
    assert Enum.count(Map.keys(page_digest_items)) == num_page_bundles
    assert page_digest_items[Module1] == "992769ebf3ba16495f70bd8cd764555d"
  end

  defp test_runtime_bundle do
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
