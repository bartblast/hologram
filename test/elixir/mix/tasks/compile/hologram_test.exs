defmodule Mix.Tasks.Compile.HologramTest do
  use Hologram.Test.BasicCase, async: true
  import Mix.Tasks.Compile.Hologram

  alias Hologram.Commons.PLT
  alias Hologram.Commons.Reflection
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.IR
  alias Hologram.Test.Fixtures.Mix.Tasks.Compile.Module1
  alias Hologram.Test.Fixtures.Mix.Tasks.Compile.Module2

  @root_dir Reflection.root_dir()
  @tmp_dir "#{Reflection.tmp_dir()}/#{__MODULE__}/run_1"

  setup do
    clean_dir(@tmp_dir)
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
    call_graph_dump_path = "#{@tmp_dir}/build/call_graph.bin"
    assert File.exists?(call_graph_dump_path)

    call_graph = CallGraph.start()
    CallGraph.load(call_graph, call_graph_dump_path)

    assert CallGraph.inbound_remote_edges(call_graph, Module2) == [
             %Graph.Edge{v1: {Module1, :__layout_module__, 0}, v2: Module2}
           ]
  end

  defp test_ir_plt do
    ir_plt_dump_path = "#{@tmp_dir}/build/ir.plt"
    assert File.exists?(ir_plt_dump_path)

    ir_plt = PLT.start()
    PLT.load(ir_plt, ir_plt_dump_path)
    assert %IR.ModuleDefinition{} = PLT.get!(ir_plt, Module2)
  end

  defp test_module_digest_plt do
    module_digest_plt_dump_path = "#{@tmp_dir}/build/module_digest.plt"
    assert File.exists?(module_digest_plt_dump_path)

    module_digest_plt = PLT.start()
    PLT.load(module_digest_plt, module_digest_plt_dump_path)

    bit_size =
      module_digest_plt
      |> PLT.get!(Module2)
      |> bit_size()

    assert bit_size == 256
  end

  defp test_page_bundles do
    num_page_bundles =
      "#{@tmp_dir}/bundle/hologram/page-????????????????????????????????.js"
      |> Path.wildcard()
      |> Enum.count()

    assert num_page_bundles > 1

    num_page_source_maps =
      "#{@tmp_dir}/bundle/hologram/page-????????????????????????????????.js.map"
      |> Path.wildcard()
      |> Enum.count()

    assert num_page_source_maps == num_page_bundles

    num_page_bundles
  end

  defp test_page_digest_plt(expected_num_page_bundles) do
    page_digest_dump_file =
      Path.join([@tmp_dir, "build", Reflection.page_digest_plt_dump_file_name()])

    assert File.exists?(page_digest_dump_file)

    page_digest_plt = PLT.start()
    PLT.load(page_digest_plt, page_digest_dump_file)
    page_digest_items = PLT.get_all(page_digest_plt)

    num_page_bundles =
      page_digest_items
      |> Map.keys()
      |> Enum.count()

    assert num_page_bundles == expected_num_page_bundles

    assert page_digest_items[Module1] =~ ~r/^[0-9a-f]{32}$/
  end

  defp test_runtime_bundle do
    num_runtime_bundles =
      "#{@tmp_dir}/bundle/hologram/runtime-????????????????????????????????.js"
      |> Path.wildcard()
      |> Enum.count()

    assert num_runtime_bundles == 1

    num_runtime_source_maps =
      "#{@tmp_dir}/bundle/hologram/runtime-????????????????????????????????.js.map"
      |> Path.wildcard()
      |> Enum.count()

    assert num_runtime_source_maps == 1
  end

  # There are two tests in one test block here, because setup for the second test is expensive.
  test "compile/1" do
    opts = [
      assets_source_dir: "#{@root_dir}/assets",
      build_dir: "#{@tmp_dir}/build",
      bundle_dir: "#{@tmp_dir}/bundle/hologram",
      esbuild_path: "#{@root_dir}/assets/node_modules/.bin/esbuild",
      js_formatter_bin_path: "#{@root_dir}/assets/node_modules/.bin/prettier",
      js_formatter_config_path: "#{@root_dir}/assets/.prettierrc.json",
      js_source_dir: "#{@root_dir}/assets/js",
      tmp_dir: "#{@tmp_dir}/tmp"
    ]

    # Test case 1: when there are no previous build artifacts
    compile(opts)
    test_build_artifacts()

    # Test case 2: when there are previous build artifacts
    compile(opts)
    test_build_artifacts()
  end
end
