# defmodule Mix.Tasks.Compile.HologramTest do
#   use Hologram.Test.BasicCase, async: true
#   import Mix.Tasks.Compile.Hologram

#   alias Hologram.Commons.PLT
#   alias Hologram.Commons.Reflection
#   alias Hologram.Compiler.CallGraph
#   alias Hologram.Compiler.IR
#   alias Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module2

#   @test_dir Path.join(Reflection.tmp_dir(), to_string(__MODULE__))

#   @assets_dir Path.join(@test_dir, "assets")
#   @build_dir Path.join(@test_dir, "build")
#   @root_dir Reflection.root_dir()
#   @static_dir Path.join(@test_dir, "static")
#   @tmp_dir Path.join(@test_dir, "tmp")

#   defp test_build_artifacts do
#     test_dirs()
#     test_module_beam_path_plt()
#     test_module_digest_plt()
#     test_ir_plt()
#     test_call_graph()
#     test_js_deps()
#   end

#   defp test_call_graph do
#     call_graph_dump_path = Path.join(@build_dir, "call_graph.bin")
#     assert File.exists?(call_graph_dump_path)

#     call_graph = CallGraph.start()
#     CallGraph.load(call_graph, call_graph_dump_path)

#     assert CallGraph.has_vertex?(call_graph, Module2)
#   end

#   defp test_dirs do
#     assert File.exists?(@build_dir)
#     assert File.exists?(@static_dir)
#     assert File.exists?(@tmp_dir)
#   end

#   defp test_ir_plt do
#     ir_plt_dump_path = Path.join(@build_dir, "ir.plt")
#     assert File.exists?(ir_plt_dump_path)

#     ir_plt = PLT.start()
#     PLT.load(ir_plt, ir_plt_dump_path)

#     assert %IR.ModuleDefinition{module: %IR.AtomType{value: Module2}} = PLT.get!(ir_plt, Module2)
#   end

#   defp test_js_deps do
#     assert @assets_dir
#            |> Path.join("node_modules")
#            |> File.exists?()
#   end

#   defp test_module_beam_path_plt do
#     module_beam_path_plt_dump_path = Path.join(@build_dir, "module_beam_path.plt")
#     assert File.exists?(module_beam_path_plt_dump_path)

#     module_beam_path_plt = PLT.start()
#     PLT.load(module_beam_path_plt, module_beam_path_plt_dump_path)
#     assert PLT.get!(module_beam_path_plt, Module2) == :code.which(Module2)
#   end

#   defp test_module_digest_plt do
#     module_digest_plt_dump_path = Path.join(@build_dir, "module_digest.plt")
#     assert File.exists?(module_digest_plt_dump_path)

#     module_digest_plt = PLT.start()
#     PLT.load(module_digest_plt, module_digest_plt_dump_path)
#     assert <<_digest::256>> = PLT.get!(module_digest_plt, Module2)
#   end

#   setup do
#     clean_dir(@test_dir)
#     File.mkdir!(@assets_dir)

#     lib_package_json_path = Path.join([@root_dir, "assets", "package.json"])
#     fixture_package_json_path = Path.join(@assets_dir, "package.json")
#     File.cp!(lib_package_json_path, fixture_package_json_path)

#     opts = [
#       assets_dir: @assets_dir,
#       build_dir: @build_dir,
#       static_dir: @static_dir,
#       tmp_dir: @tmp_dir
#     ]

#     [opts: opts]
#   end

#   test "run/1", %{opts: opts} do
#     # Test case 1: when there are no previous build artifacts
#     run(opts)
#     test_build_artifacts()

#     # Test case 2: when there are previous build artifacts
#     run(opts)
#     test_build_artifacts()
#   end
# end

# defmodule Mix.Tasks.Compile.HologramTest do
#   alias Hologram.Test.Fixtures.Mix.Tasks.Compile.Module1

#   @root_dir Reflection.root_dir()

#   setup do
#     opts = [
#       assets_dir: "#{@root_dir}/assets",
#       esbuild_path: "#{@root_dir}/assets/node_modules/.bin/esbuild",
#       js_formatter_bin_path: "#{@root_dir}/assets/node_modules/.bin/prettier",
#       js_formatter_config_path: "#{@root_dir}/assets/.prettierrc.json",
#       js_source_dir: "#{@root_dir}/assets/js",
#       static_dir: "#{@test_dir}/bundle/hologram",
#       tmp_dir: "#{@test_dir}/tmp"
#     ]

#     File.mkdir!(opts[:build_dir])

#     [opts: opts]
#   end

#   defp test_build_artifacts do
#     num_page_bundles = test_page_bundles()
#     test_runtime_bundle()

#     ...
#     test_page_digest_plt(num_page_bundles)
#   end

#   defp test_page_bundles do
#     num_page_bundles =
#       "#{@test_dir}/bundle/hologram/page-????????????????????????????????.js"
#       |> Path.wildcard()
#       |> Enum.count()

#     assert num_page_bundles > 1

#     num_page_source_maps =
#       "#{@test_dir}/bundle/hologram/page-????????????????????????????????.js.map"
#       |> Path.wildcard()
#       |> Enum.count()

#     assert num_page_source_maps == num_page_bundles

#     num_page_bundles
#   end

#   defp test_page_digest_plt(expected_num_page_bundles) do
#     page_digest_dump_path =
#       Path.join([@test_dir, "build", Reflection.page_digest_plt_dump_file_name()])

#     assert File.exists?(page_digest_dump_path)

#     page_digest_plt = PLT.start()
#     PLT.load(page_digest_plt, page_digest_dump_path)
#     page_digest_items = PLT.get_all(page_digest_plt)

#     num_page_bundles =
#       page_digest_items
#       |> Map.keys()
#       |> Enum.count()

#     assert num_page_bundles == expected_num_page_bundles

#     assert page_digest_items[Module1] =~ ~r/^[0-9a-f]{32}$/
#   end

#   defp test_runtime_bundle do
#     num_runtime_bundles =
#       "#{@test_dir}/bundle/hologram/runtime-????????????????????????????????.js"
#       |> Path.wildcard()
#       |> Enum.count()

#     assert num_runtime_bundles == 1

#     num_runtime_source_maps =
#       "#{@test_dir}/bundle/hologram/runtime-????????????????????????????????.js.map"
#       |> Path.wildcard()
#       |> Enum.count()

#     assert num_runtime_source_maps == 1
#   end
# end
