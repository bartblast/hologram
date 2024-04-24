defmodule Hologram.CompilerTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler

  alias Hologram.Commons.PLT
  alias Hologram.Commons.Reflection
  alias Hologram.Commons.TaskUtils
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.IR

  alias Hologram.Test.Fixtures.Compiler.Module1
  alias Hologram.Test.Fixtures.Compiler.Module11
  alias Hologram.Test.Fixtures.Compiler.Module2
  alias Hologram.Test.Fixtures.Compiler.Module3
  alias Hologram.Test.Fixtures.Compiler.Module4
  alias Hologram.Test.Fixtures.Compiler.Module5
  alias Hologram.Test.Fixtures.Compiler.Module6
  alias Hologram.Test.Fixtures.Compiler.Module7
  alias Hologram.Test.Fixtures.Compiler.Module8
  alias Hologram.Test.Fixtures.Compiler.Module9

  @assets_dir Path.join(Reflection.root_dir(), "assets")
  @js_dir Path.join(@assets_dir, "js")
  @tmp_dir Reflection.tmp_dir()

  defp setup_js_deps_test(test_tmp_subdir) do
    tmp_dir = Path.join(@tmp_dir, test_tmp_subdir)
    assets_dir = Path.join(tmp_dir, "assets")
    build_dir = Path.join(tmp_dir, "build")

    clean_dir(tmp_dir)
    File.mkdir!(assets_dir)
    File.mkdir!(build_dir)

    lib_package_json_path = Path.join(@assets_dir, "package.json")
    fixture_package_json_path = Path.join(assets_dir, "package.json")
    File.cp!(lib_package_json_path, fixture_package_json_path)

    [assets_dir: assets_dir, build_dir: build_dir]
  end

  setup_all do
    module_beam_path_plt = build_module_beam_path_plt()
    ir_plt = build_ir_plt(module_beam_path_plt)

    call_graph = CallGraph.start()

    Reflection.list_elixir_modules()
    |> TaskUtils.async_many(fn module ->
      CallGraph.build(call_graph, PLT.get!(ir_plt, module))
    end)
    |> Task.await_many(:infinity)

    [
      call_graph: call_graph,
      ir_plt: ir_plt,
      module_beam_path_plt: module_beam_path_plt,
      runtime_mfas: list_runtime_mfas(call_graph)
    ]
  end

  test "build_ir_plt/1", %{ir_plt: ir_plt} do
    assert %PLT{} = ir_plt

    assert %IR.ModuleDefinition{module: %IR.AtomType{value: Hologram.Compiler}} =
             PLT.get!(ir_plt, Hologram.Compiler)
  end

  test "build_module_beam_path_plt/0", %{module_beam_path_plt: module_beam_path_plt} do
    assert %PLT{} = module_beam_path_plt
    assert PLT.get!(module_beam_path_plt, Hologram.Compiler) == :code.which(Hologram.Compiler)
  end

  describe "build_module_digest_plt!/0" do
    setup %{module_beam_path_plt: module_beam_path_plt} do
      [module_beam_path_plt: PLT.clone(module_beam_path_plt)]
    end

    test "builds module digest PLT", %{module_beam_path_plt: module_beam_path_plt} do
      assert plt = %PLT{} = build_module_digest_plt!(module_beam_path_plt)

      assert <<_digest::256>> = PLT.get!(plt, Hologram.Commons.Reflection)
      assert <<_digest::256>> = PLT.get!(plt, Hologram.Compiler)
    end

    test "adds missing module BEAM path PLT entries", %{
      module_beam_path_plt: module_beam_path_plt
    } do
      PLT.delete(module_beam_path_plt, Hologram.Compiler)
      build_module_digest_plt!(module_beam_path_plt)

      assert PLT.get!(module_beam_path_plt, Hologram.Compiler) ==
               :code.which(Hologram.Compiler)
    end
  end

  test "build_runtime_js/3", %{ir_plt: ir_plt, runtime_mfas: runtime_mfas} do
    js = build_runtime_js(runtime_mfas, ir_plt, @js_dir)

    assert String.contains?(
             js,
             ~s/Interpreter.defineElixirFunction("Enum", "into", 2, "public"/
           )

    assert String.contains?(
             js,
             ~s/Interpreter.defineElixirFunction("Enum", "into_protocol", 2, "private"/
           )

    assert String.contains?(js, ~s/Interpreter.defineErlangFunction("erlang", "error", 1/)

    assert String.contains?(
             js,
             ~s/Interpreter.defineNotImplementedErlangFunction("erpc", "call", 4/
           )
  end

  test "create_runtime_entry_file/3", %{ir_plt: ir_plt, runtime_mfas: runtime_mfas} do
    test_tmp_subdir = "test_create_runtime_entry_file_3"

    opts = [
      js_dir: @js_dir,
      tmp_dir: Path.join(@tmp_dir, test_tmp_subdir)
    ]

    clean_dir(opts[:tmp_dir])

    entry_file_path = create_runtime_entry_file(runtime_mfas, ir_plt, opts)

    assert entry_file_path
           |> File.read!()
           |> String.contains?("Interpreter.defineElixirFunction")
  end

  test "diff_module_digest_plts/2" do
    old_plt =
      PLT.start()
      |> PLT.put(:module_1, :digest_1)
      |> PLT.put(:module_3, :digest_3a)
      |> PLT.put(:module_5, :digest_5)
      |> PLT.put(:module_6, :digest_6a)
      |> PLT.put(:module_7, :digest_7)

    new_plt =
      PLT.start()
      |> PLT.put(:module_1, :digest_1)
      |> PLT.put(:module_2, :digest_2)
      |> PLT.put(:module_3, :digest_3b)
      |> PLT.put(:module_4, :digest_4)
      |> PLT.put(:module_6, :digest_6b)

    assert diff_module_digest_plts(old_plt, new_plt) == %{
             added_modules: [:module_2, :module_4],
             removed_modules: [:module_5, :module_7],
             updated_modules: [:module_3, :module_6]
           }
  end

  test "group_mfas_by_module/1" do
    mfas = [
      {:module_1, :fun_a, 1},
      {:module_2, :fun_b, 2},
      {:module_3, :fun_c, 3},
      {:module_1, :fun_d, 3},
      {:module_2, :fun_e, 1},
      {:module_3, :fun_f, 2}
    ]

    assert group_mfas_by_module(mfas) == %{
             module_1: [{:module_1, :fun_a, 1}, {:module_1, :fun_d, 3}],
             module_2: [{:module_2, :fun_b, 2}, {:module_2, :fun_e, 1}],
             module_3: [{:module_3, :fun_c, 3}, {:module_3, :fun_f, 2}]
           }
  end

  describe "install_js_deps/1" do
    setup do
      setup_js_deps_test("test_install_js_deps_1")
    end

    test "installs deps in node_modules dir and creates package-lock.json file", %{
      assets_dir: assets_dir,
      build_dir: build_dir
    } do
      install_js_deps(assets_dir, build_dir)

      node_modules_dir = Path.join(assets_dir, "node_modules")
      assert File.exists?(node_modules_dir)

      package_lock_json_path = Path.join(assets_dir, "package-lock.json")
      assert File.exists?(package_lock_json_path)
    end

    test "creates a file containing the digest of package.json", %{
      assets_dir: assets_dir,
      build_dir: build_dir
    } do
      install_js_deps(assets_dir, build_dir)

      package_json_digest_path = Path.join(build_dir, "package_json_digest.bin")
      assert File.exists?(package_json_digest_path)
    end
  end

  test "list_page_mfas/2" do
    module_5_ir = IR.for_module(Module5)
    module_6_ir = IR.for_module(Module6)
    module_7_ir = IR.for_module(Module7)

    call_graph =
      CallGraph.start()
      |> CallGraph.build(module_5_ir)
      |> CallGraph.build(module_6_ir)
      |> CallGraph.build(module_7_ir)

    sorted_result =
      Module5
      |> list_page_mfas(call_graph)
      |> Enum.sort()

    assert sorted_result == [
             {Enum, :reverse, 1},
             {Enum, :to_list, 1},
             {Module5, :__layout_module__, 0},
             {Module5, :__layout_props__, 0},
             {Module5, :__props__, 0},
             {Module5, :__route__, 0},
             {Module5, :action, 3},
             {Module5, :template, 0},
             {Module6, :__props__, 0},
             {Module6, :action, 3},
             {Module6, :init, 2},
             {Module6, :template, 0},
             {Module7, :my_fun_7a, 2},
             {Kernel, :inspect, 1},
             {:erlang, :hd, 1}
           ]
  end

  describe "list_runtime_mfas/1" do
    test "includes MFAs that are reachable by Elixir functions used by the runtime", %{
      runtime_mfas: result
    } do
      assert {Enum, :into, 2} in result
      assert {Enum, :into_protocol, 2} in result
      assert {:lists, :foldl, 3} in result

      assert {Enum, :to_list, 1} in result
      assert {Enum, :reverse, 1} in result
      assert {:lists, :reverse, 1} in result
    end

    test "includes MFAs that are reachable by Erlang functions used by the runtime", %{
      runtime_mfas: result
    } do
      assert {:erlang, :==, 2} in result
      assert {:erlang, :error, 2} in result
    end

    test "removes duplicates", %{runtime_mfas: result} do
      count = Enum.count(result, &(&1 == {Access, :get, 2}))
      assert count == 1
    end

    test "excludes MFAs with non-existing modules", %{call_graph: call_graph} do
      call_graph_clone = CallGraph.clone(call_graph)

      call_graph_clone
      |> CallGraph.add_edge({Enum, :into, 2}, {Calendar.ISO, :dummy_function_1, 1})
      |> CallGraph.add_edge({Enum, :into, 2}, {NonExistingModuleFixture, :dummy_function_2, 2})
      |> CallGraph.add_edge({Enum, :into, 2}, {:maps, :dummy_function_3, 3})
      |> CallGraph.add_edge(
        {Enum, :into, 2},
        {:non_existing_module_fixture, :dummy_function_4, 4}
      )

      result = list_runtime_mfas(call_graph_clone)

      assert {Calendar.ISO, :dummy_function_1, 1} in result
      refute {NonExistingModuleFixture, :dummy_function_2, 2} in result
      assert {:maps, :dummy_function_3, 3} in result
      refute {:non_existing_module_fixture, :dummy_function_4, 4} in result
    end

    test "sorts results", %{runtime_mfas: result} do
      assert hd(result) == {Access, :get, 2}
    end
  end

  describe "maybe_install_js_deps/1" do
    setup do
      setup_js_deps_test("test_maybe_install_js_deps_1")
    end

    test "package_json_digest.bin file doesn't exist", %{
      assets_dir: assets_dir,
      build_dir: build_dir
    } do
      install_js_deps(assets_dir, build_dir)

      package_json_digest_path = Path.join(build_dir, "package_json_digest.bin")
      File.rm!(package_json_digest_path)

      assert maybe_install_js_deps(assets_dir, build_dir) == :ok
      assert File.exists?(package_json_digest_path)
    end

    test "package-lock.json file doesn't exist", %{assets_dir: assets_dir, build_dir: build_dir} do
      install_js_deps(assets_dir, build_dir)

      package_lock_json_path = Path.join(assets_dir, "package-lock.json")
      File.rm!(package_lock_json_path)

      assert maybe_install_js_deps(assets_dir, build_dir) == :ok
      assert File.exists?(package_lock_json_path)
    end

    test "package.json file changed", %{assets_dir: assets_dir, build_dir: build_dir} do
      install_js_deps(assets_dir, build_dir)

      package_json_digest_path = Path.join(build_dir, "package_json_digest.bin")
      package_json_digest = File.read!(package_json_digest_path)

      package_json_path = Path.join(assets_dir, "package.json")
      File.write!(package_json_path, "{}")

      assert maybe_install_js_deps(assets_dir, build_dir) == :ok
      assert File.read!(package_json_digest_path) != package_json_digest
    end

    test "install is not needed", %{assets_dir: assets_dir, build_dir: build_dir} do
      install_js_deps(assets_dir, build_dir)

      package_json_digest_path = Path.join(build_dir, "package_json_digest.bin")
      package_json_digest_mtime = File.stat!(package_json_digest_path).mtime

      assert maybe_install_js_deps(assets_dir, build_dir) == nil
      assert File.stat!(package_json_digest_path).mtime == package_json_digest_mtime
    end
  end

  describe "maybe_load_call_graph/1" do
    setup do
      test_tmp_subdir = "test_maybe_load_call_graph_1"

      build_dir = Path.join(@tmp_dir, test_tmp_subdir)
      clean_dir(build_dir)

      dump_path = Path.join([@tmp_dir, test_tmp_subdir, "call_graph.bin"])

      [build_dir: build_dir, dump_path: dump_path]
    end

    test "dump file doesn't exist", %{build_dir: build_dir, dump_path: dump_path} do
      assert {call_graph = %CallGraph{}, ^dump_path} = maybe_load_call_graph(build_dir)
      assert CallGraph.get_graph(call_graph) == Graph.new()
    end

    test "dump file exists", %{build_dir: build_dir, call_graph: call_graph, dump_path: dump_path} do
      CallGraph.dump(call_graph, dump_path)

      assert {loaded_call_graph = %CallGraph{}, ^dump_path} = maybe_load_call_graph(build_dir)
      assert CallGraph.get_graph(loaded_call_graph) == CallGraph.get_graph(call_graph)
    end
  end

  describe "maybe_load_ir_plt/1" do
    setup do
      test_tmp_subdir = "test_maybe_load_ir_plt_1"

      build_dir = Path.join(@tmp_dir, test_tmp_subdir)
      clean_dir(build_dir)

      dump_path = Path.join([@tmp_dir, test_tmp_subdir, "ir.plt"])

      [build_dir: build_dir, dump_path: dump_path]
    end

    test "dump file doesn't exist", %{build_dir: build_dir, dump_path: dump_path} do
      assert {plt = %PLT{}, ^dump_path} = maybe_load_ir_plt(build_dir)
      assert PLT.get_all(plt) == %{}
    end

    test "dump file exists", %{build_dir: build_dir, dump_path: dump_path, ir_plt: ir_plt} do
      PLT.dump(ir_plt, dump_path)

      assert {plt = %PLT{}, ^dump_path} = maybe_load_ir_plt(build_dir)
      assert PLT.get_all(plt) == PLT.get_all(ir_plt)
    end
  end

  describe "maybe_load_module_beam_path_plt/1" do
    setup do
      test_tmp_subdir = "test_maybe_load_module_beam_path_plt_1"

      build_dir = Path.join(@tmp_dir, test_tmp_subdir)
      clean_dir(build_dir)

      dump_path = Path.join([@tmp_dir, test_tmp_subdir, "module_beam_path.plt"])

      [build_dir: build_dir, dump_path: dump_path]
    end

    test "dump file doesn't exist", %{build_dir: build_dir, dump_path: dump_path} do
      assert {plt = %PLT{}, ^dump_path} = maybe_load_module_beam_path_plt(build_dir)
      assert PLT.get_all(plt) == %{}
    end

    test "dump file exists", %{
      build_dir: build_dir,
      dump_path: dump_path,
      module_beam_path_plt: module_beam_path_plt
    } do
      PLT.dump(module_beam_path_plt, dump_path)

      assert {plt = %PLT{}, ^dump_path} = maybe_load_module_beam_path_plt(build_dir)
      assert PLT.get_all(plt) == PLT.get_all(module_beam_path_plt)
    end
  end

  describe "maybe_load_module_digest_plt/1" do
    setup do
      test_tmp_subdir = "test_maybe_load_module_digest_plt_1"

      build_dir = Path.join(@tmp_dir, test_tmp_subdir)
      clean_dir(build_dir)

      dump_path = Path.join([@tmp_dir, test_tmp_subdir, "module_digest.plt"])

      [build_dir: build_dir, dump_path: dump_path]
    end

    test "dump file doesn't exist", %{build_dir: build_dir, dump_path: dump_path} do
      assert {plt = %PLT{}, ^dump_path} = maybe_load_module_digest_plt(build_dir)
      assert PLT.get_all(plt) == %{}
    end

    test "dump file exists", %{build_dir: build_dir, dump_path: dump_path} do
      PLT.start()
      |> PLT.put(:a, 1)
      |> PLT.put(:b, 2)
      |> PLT.dump(dump_path)

      assert {plt = %PLT{}, ^dump_path} = maybe_load_module_digest_plt(build_dir)
      assert PLT.get_all(plt) == %{a: 1, b: 2}
    end
  end

  describe "patch_ir_plt!/3" do
    setup %{module_beam_path_plt: module_beam_path_plt} do
      module_beam_path_plt_clone = PLT.clone(module_beam_path_plt)

      ir_plt =
        PLT.start()
        |> PLT.put(:module_5, :ir_5)
        |> PLT.put(:module_6, :ir_6)
        |> PLT.put(Module3, :ir_3)
        |> PLT.put(:module_7, :ir_7)
        |> PLT.put(:module_8, :ir_8)
        |> PLT.put(Module4, :ir_4)

      module_digests_diff = %{
        added_modules: [Module1, Module2],
        removed_modules: [:module_5, :module_7],
        updated_modules: [Module3, Module4]
      }

      patch_ir_plt!(ir_plt, module_digests_diff, module_beam_path_plt_clone)

      [ir_plt: ir_plt]
    end

    test "adds entries of added modules", %{ir_plt: ir_plt} do
      assert PLT.get(ir_plt, Module1) ==
               {:ok,
                %IR.ModuleDefinition{
                  module: %IR.AtomType{
                    value: Module1
                  },
                  body: %IR.Block{expressions: []}
                }}

      assert PLT.get(ir_plt, Module2) ==
               {:ok,
                %IR.ModuleDefinition{
                  module: %IR.AtomType{
                    value: Module2
                  },
                  body: %IR.Block{expressions: []}
                }}
    end

    test "removes entries of removed modules", %{ir_plt: ir_plt} do
      assert PLT.get(ir_plt, :module_5) == :error
      assert PLT.get(ir_plt, :module_7) == :error
    end

    test "updates entries of updated modules", %{ir_plt: ir_plt} do
      assert PLT.get(ir_plt, Module3) ==
               {:ok,
                %IR.ModuleDefinition{
                  module: %IR.AtomType{
                    value: Module3
                  },
                  body: %IR.Block{expressions: []}
                }}

      assert PLT.get(ir_plt, Module4) ==
               {:ok,
                %IR.ModuleDefinition{
                  module: %IR.AtomType{
                    value: Module4
                  },
                  body: %IR.Block{expressions: []}
                }}
    end

    test "doesn't change entries of unchanged modules", %{ir_plt: ir_plt} do
      assert PLT.get(ir_plt, :module_6) == {:ok, :ir_6}
      assert PLT.get(ir_plt, :module_8) == {:ok, :ir_8}
    end
  end

  test "prune_module_def/2" do
    module_def_ir = IR.for_module(Module8)

    module_def_ir_fixture = %{
      module_def_ir
      | body: %IR.Block{
          expressions: [
            %IR.IgnoredExpression{type: :public_macro_definition} | module_def_ir.body.expressions
          ]
        }
    }

    reachable_mfas = [
      {Module8, :fun_2, 2},
      {Module8, :fun_3, 1}
    ]

    assert prune_module_def(module_def_ir_fixture, reachable_mfas) == %IR.ModuleDefinition{
             module: %IR.AtomType{value: Module8},
             body: %IR.Block{
               expressions: [
                 %IR.FunctionDefinition{
                   name: :fun_2,
                   arity: 2,
                   visibility: :public,
                   clause: %IR.FunctionClause{
                     params: [
                       %IR.AtomType{value: :a},
                       %IR.AtomType{value: :b}
                     ],
                     guards: [],
                     body: %IR.Block{
                       expressions: [%IR.IntegerType{value: 3}]
                     }
                   }
                 },
                 %IR.FunctionDefinition{
                   name: :fun_2,
                   arity: 2,
                   visibility: :public,
                   clause: %IR.FunctionClause{
                     params: [
                       %IR.AtomType{value: :b},
                       %IR.AtomType{value: :c}
                     ],
                     guards: [],
                     body: %IR.Block{
                       expressions: [%IR.IntegerType{value: 4}]
                     }
                   }
                 },
                 %IR.FunctionDefinition{
                   name: :fun_3,
                   arity: 1,
                   visibility: :public,
                   clause: %IR.FunctionClause{
                     params: [%IR.Variable{name: :x}],
                     guards: [],
                     body: %IR.Block{
                       expressions: [%IR.Variable{name: :x}]
                     }
                   }
                 }
               ]
             }
           }
  end

  describe "validate_page_modules/1" do
    test "doesn't raise any error if all pages have a route and a layout specified" do
      assert validate_page_modules([Module9, Module11]) == :ok
    end

    test "raises error if any of the pages doesn't have a route specified" do
      # Inline fixture used, because file fixture would raise error in compile.hologram Mix task tests.
      defmodule InlinePageModuleFixture1 do
        use Hologram.Page

        layout Hologram.Test.Fixtures.LayoutFixture

        @impl Page
        def template do
          ~H""
        end
      end

      expected_msg =
        "page 'Hologram.CompilerTest.InlinePageModuleFixture1' doesn't have a route specified (use the route/1 macro to fix it)"

      assert_raise Hologram.CompileError, expected_msg, fn ->
        validate_page_modules([Module11, InlinePageModuleFixture1])
      end
    end

    test "raises error if any of the pages doesn't have a layout specified" do
      # Inline fixture used, because file fixture would raise error in compile.hologram Mix task tests.
      defmodule InlinePageModuleFixture2 do
        use Hologram.Page

        route "/hologram-compilertest-inline-page-module-fixture-2"

        @impl Page
        def template do
          ~H""
        end
      end

      expected_msg =
        "page 'Hologram.CompilerTest.InlinePageModuleFixture2' doesn't have a layout module specified (use the layout/1 macro to fix it)"

      assert_raise Hologram.CompileError, expected_msg, fn ->
        validate_page_modules([Module11, InlinePageModuleFixture2])
      end
    end
  end
end

# defmodule Hologram.CompilerTest do
#   alias Hologram.Commons.PLT
#   alias Hologram.Commons.Reflection
#   alias Hologram.Commons.TaskUtils

#   alias Hologram.Test.Fixtures.Compiler.Module10
#   alias Hologram.Test.Fixtures.Compiler.Module11

#   setup_all do
#     opts = [
#       assets_dir: @assets_dir,
#       build_dir: Reflection.build_dir()
#     ]

#     maybe_install_js_deps(opts)
#   end

#   describe "build_page_js/3" do
#     test "has both Erlang and Elixir function defs" do
#       module_8_ir = IR.for_module(Module8)
#       module_9_ir = IR.for_module(Module9)
#       module_10_ir = IR.for_module(Module10)
#       map_ir = IR.for_module(Map)

#       call_graph =
#         CallGraph.start()
#         |> CallGraph.build(module_8_ir)
#         |> CallGraph.build(module_9_ir)
#         |> CallGraph.build(module_10_ir)
#         |> CallGraph.build(map_ir)

#       ir_plt =
#         PLT.start()
#         |> PLT.put(Module8, module_8_ir)
#         |> PLT.put(Module9, module_9_ir)
#         |> PLT.put(Module10, module_10_ir)
#         |> PLT.put(Map, map_ir)

#       result = build_page_js(Module9, call_graph, ir_plt, @js_dir)

#       js_fragment_1 = ~s/window.__hologramPageReachableFunctionDefs__/
#       js_fragment_2 = ~s/Interpreter.defineElixirFunction/
#       js_fragment_3 = ~s/Interpreter.defineErlangFunction/

#       assert String.contains?(result, js_fragment_1)
#       assert String.contains?(result, js_fragment_2)
#       assert String.contains?(result, js_fragment_3)
#     end

#     test "has only Elixir defs" do
#       module_6_ir = IR.for_module(Module6)
#       module_11_ir = IR.for_module(Module11)

#       call_graph =
#         CallGraph.start()
#         |> CallGraph.build(module_6_ir)
#         |> CallGraph.build(module_11_ir)

#       ir_plt =
#         PLT.start()
#         |> PLT.put(Module6, module_6_ir)
#         |> PLT.put(Module11, module_11_ir)

#       result = build_page_js(Module11, call_graph, ir_plt, @js_dir)

#       js_fragment_1 = ~s/window.__hologramPageReachableFunctionDefs__/
#       js_fragment_2 = ~s/Interpreter.defineElixirFunction/
#       js_fragment_3 = ~s/Interpreter.defineErlangFunction/

#       assert String.contains?(result, js_fragment_1)
#       assert String.contains?(result, js_fragment_2)
#       refute String.contains?(result, js_fragment_3)
#     end
#   end

#   describe "bundle/4" do
#     @esbuild_path Reflection.root_dir() <> "/assets/node_modules/.bin/esbuild"
#     @js_formatter_bin_path Reflection.root_dir() <> "/assets/node_modules/.bin/prettier"
#     @js_formatter_config_path Reflection.root_dir() <> "/assets/.prettierrc.json"
#     @js_code "const myVar  =  123"
#     @entry_name "my_entry"
#     @tmp_dir "#{Reflection.tmp_dir()}/#{__MODULE__}/build_4"
#     @bundle_name "my_bundle"

#     @opts [
#       entry_name: @entry_name,
#       esbuild_path: @esbuild_path,
#       js_formatter_bin_path: @js_formatter_bin_path,
#       js_formatter_config_path: @js_formatter_config_path,
#       tmp_dir: @tmp_dir,
#       static_dir: @tmp_dir,
#       bundle_name: @bundle_name
#     ]

#     setup do
#       clean_dir(@tmp_dir)
#       :ok
#     end

#     test "creates tmp and bundle nested path dirs if they don't exist" do
#       opts =
#         @opts
#         |> Keyword.put(:tmp_dir, "#{@tmp_dir}/nested_1/nested_2/nested_3")
#         |> Keyword.put(:static_dir, "#{@tmp_dir}/nested_4/nested_5/nested_6")

#       assert bundle(@js_code, opts)
#       assert File.exists?(opts[:tmp_dir])
#       assert File.exists?(opts[:static_dir])
#     end

#     test "formats entry file" do
#       bundle(@js_code, @opts)

#       entry_file_path = "#{@tmp_dir}/#{@entry_name}.entry.js"
#       assert File.read!(entry_file_path) == "const myVar = 123;\n"
#     end

#     test "bundles files" do
#       assert bundle(@js_code, @opts) ==
#                {"f499a92d06ea057f92198bef2cba2822",
#                 bundle_path = "#{@tmp_dir}/my_bundle-f499a92d06ea057f92198bef2cba2822.js",
#                 source_map_path = "#{@tmp_dir}/my_bundle-f499a92d06ea057f92198bef2cba2822.js.map"}

#       assert File.read!(bundle_path) == """
#              (()=>{})();
#              //# sourceMappingURL=my_bundle-f499a92d06ea057f92198bef2cba2822.js.map
#              """

#       assert File.read!(source_map_path) == """
#              {
#                "version": 3,
#                "sources": [],
#                "sourcesContent": [],
#                "mappings": "",
#                "names": []
#              }
#              """
#     end
#   end
# end
