defmodule Hologram.CompilerTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler

  alias Hologram.Commons.PLT
  alias Hologram.Commons.Reflection
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.IR

  alias Hologram.Test.Fixtures.Compiler.Module1
  alias Hologram.Test.Fixtures.Compiler.Module10
  alias Hologram.Test.Fixtures.Compiler.Module11
  alias Hologram.Test.Fixtures.Compiler.Module12
  alias Hologram.Test.Fixtures.Compiler.Module2
  alias Hologram.Test.Fixtures.Compiler.Module3
  alias Hologram.Test.Fixtures.Compiler.Module4
  alias Hologram.Test.Fixtures.Compiler.Module5
  alias Hologram.Test.Fixtures.Compiler.Module6
  alias Hologram.Test.Fixtures.Compiler.Module7
  alias Hologram.Test.Fixtures.Compiler.Module8
  alias Hologram.Test.Fixtures.Compiler.Module9

  @assets_dir Path.join([Reflection.root_path(), "assets"])
  @source_dir Path.join([@assets_dir, "js"])
  @erlang_source_dir Path.join([@source_dir, "erlang"])

  setup_all do
    install_js_deps(@assets_dir)
    :ok
  end

  describe "build_erlang_function_definition/4" do
    test ":erlang module function that is implemented" do
      output = build_erlang_function_definition(:erlang, :+, 2, @erlang_source_dir)

      assert output == """
             Interpreter.defineErlangFunction("Erlang", "+", 2, (left, right) => {
                 const [type, leftValue, rightValue] = Type.maybeNormalizeNumberTerms(
                   left,
                   right,
                 );

                 const result = leftValue.value + rightValue.value;

                 return type === "float" ? Type.float(result) : Type.integer(result);
               });\
             """
    end

    test ":erlang module function that is not implemented" do
      output = build_erlang_function_definition(:erlang, :not_implemented, 2, @erlang_source_dir)

      assert output ==
               ~s/Interpreter.defineNotImplementedErlangFunction("erlang", "Erlang", "not_implemented", 2);/
    end

    test ":maps module function that is implemented" do
      output = build_erlang_function_definition(:maps, :get, 2, @erlang_source_dir)

      assert output == """
             Interpreter.defineErlangFunction("Erlang_Maps", "get", 2, (key, map) => {
                 if (!Type.isMap(map)) {
                   Interpreter.raiseBadMapError(map);
                 }

                 const encodedKey = Type.encodeMapKey(key);

                 if (map.data[encodedKey]) {
                   return map.data[encodedKey][1];
                 }

                 Interpreter.raiseKeyError(
                   `key ${Interpreter.inspect(key)} not found in ${Interpreter.inspect(
                     map,
                   )}`,
                 );
               });\
             """
    end

    test ":maps module function that is not implemented" do
      output = build_erlang_function_definition(:maps, :not_implemented, 2, @erlang_source_dir)

      assert output ==
               ~s/Interpreter.defineNotImplementedErlangFunction("maps", "Erlang_Maps", "not_implemented", 2);/
    end
  end

  test "build_module_digest_plt/0" do
    assert %PLT{} = plt = build_module_digest_plt()
    assert {:ok, <<_digest::256>>} = PLT.get(plt, Hologram.Compiler)
  end

  describe "build_page_js/3" do
    test "has both Erlang and Elixir function defs" do
      module_8_ir = IR.for_module(Module8)
      module_9_ir = IR.for_module(Module9)
      module_10_ir = IR.for_module(Module10)
      map_ir = IR.for_module(Map)

      call_graph =
        CallGraph.start()
        |> CallGraph.build(module_8_ir)
        |> CallGraph.build(module_9_ir)
        |> CallGraph.build(module_10_ir)
        |> CallGraph.build(map_ir)

      ir_plt =
        PLT.start()
        |> PLT.put(Module8, module_8_ir)
        |> PLT.put(Module9, module_9_ir)
        |> PLT.put(Module10, module_10_ir)
        |> PLT.put(Map, map_ir)

      result = build_page_js(Module9, call_graph, ir_plt, @source_dir)

      js_fragment_1 = ~s/window.__hologramPageReachableFunctionDefs__/
      js_fragment_2 = ~s/Interpreter.defineElixirFunction/
      js_fragment_3 = ~s/Interpreter.defineErlangFunction/

      assert String.contains?(result, js_fragment_1)
      assert String.contains?(result, js_fragment_2)
      assert String.contains?(result, js_fragment_3)
    end

    test "has only Elixir defs" do
      module_6_ir = IR.for_module(Module6)
      module_11_ir = IR.for_module(Module11)

      call_graph =
        CallGraph.start()
        |> CallGraph.build(module_6_ir)
        |> CallGraph.build(module_11_ir)

      ir_plt =
        PLT.start()
        |> PLT.put(Module6, module_6_ir)
        |> PLT.put(Module11, module_11_ir)

      result = build_page_js(Module11, call_graph, ir_plt, @source_dir)

      js_fragment_1 = ~s/window.__hologramPageReachableFunctionDefs__/
      js_fragment_2 = ~s/Interpreter.defineElixirFunction/
      js_fragment_3 = ~s/Interpreter.defineErlangFunction/

      assert String.contains?(result, js_fragment_1)
      assert String.contains?(result, js_fragment_2)
      refute String.contains?(result, js_fragment_3)
    end

    test "filters out modules without BEAM files" do
      module_6_ir = IR.for_module(Module6)
      module_7_ir = IR.for_module(Module7)
      module_12_ir = IR.for_module(Module12)

      call_graph =
        CallGraph.start()
        |> CallGraph.build(module_6_ir)
        |> CallGraph.build(module_7_ir)
        |> CallGraph.build(module_12_ir)

      ir_plt =
        PLT.start()
        |> PLT.put(Module6, module_6_ir)
        |> PLT.put(Module7, module_7_ir)
        |> PLT.put(Module12, module_12_ir)

      js_fragment_1 = ~s/defineElixirFunction("Elixir_Hologram_Test_Fixtures_Compiler_Module7"/
      js_fragment_2 = ~s/defineElixirFunction("Elixir_ModuleWithoutBEAMFile"/

      result = build_page_js(Module12, call_graph, ir_plt, @source_dir)

      assert String.contains?(result, js_fragment_1)
      refute String.contains?(result, js_fragment_2)
    end
  end

  test "build_runtime_js/3" do
    call_graph = CallGraph.start()
    ir_plt = PLT.start()
    modules = Reflection.list_elixir_modules()

    Enum.each(modules, fn module ->
      ir = IR.for_module(module)
      CallGraph.build(call_graph, ir)
      PLT.put(ir_plt, module, ir)
    end)

    js = build_runtime_js(@source_dir, call_graph, ir_plt)

    assert String.contains?(js, ~s/Interpreter.defineElixirFunction("Elixir_Enum", "into", 2/)

    assert String.contains?(
             js,
             ~s/Interpreter.defineElixirFunction("Elixir_Enum", "into_protocol", 2/
           )

    assert String.contains?(js, ~s/Interpreter.defineErlangFunction("Erlang", "error", 1/)

    assert String.contains?(
             js,
             ~s/Interpreter.defineNotImplementedErlangFunction("binary", "Erlang_Binary", "compile_pattern", 1/
           )
  end

  describe "bundle/4" do
    @esbuild_path Reflection.root_path() <> "/assets/node_modules/.bin/esbuild"
    @js_formatter_bin_path Reflection.root_path() <> "/assets/node_modules/.bin/prettier"
    @js_formatter_config_path Reflection.root_path() <> "/assets/.prettierrc.json"
    @js_code "const myVar  =  123"
    @entry_name "my_entry"
    @tmp_path "#{Reflection.tmp_path()}/#{__MODULE__}/build_4"
    @bundle_name "my_bundle"

    @opts [
      entry_name: @entry_name,
      esbuild_path: @esbuild_path,
      js_formatter_bin_path: @js_formatter_bin_path,
      js_formatter_config_path: @js_formatter_config_path,
      tmp_dir: @tmp_path,
      bundle_dir: @tmp_path,
      bundle_name: @bundle_name
    ]

    setup do
      clean_dir(@tmp_path)
      :ok
    end

    test "creates tmp and bundle nested path dirs if they don't exist" do
      opts =
        @opts
        |> Keyword.put(:tmp_dir, "#{@tmp_path}/nested_1/nested_2/nested_3")
        |> Keyword.put(:bundle_dir, "#{@tmp_path}/nested_4/nested_5/nested_6")

      assert bundle(@js_code, opts)
      assert File.exists?(opts[:tmp_dir])
      assert File.exists?(opts[:bundle_dir])
    end

    test "formats entry file" do
      bundle(@js_code, @opts)

      entry_file = "#{@tmp_path}/#{@entry_name}.entry.js"
      assert File.read!(entry_file) == "const myVar = 123;\n"
    end

    test "bundles files" do
      assert bundle(@js_code, @opts) ==
               {"957e59b82bd39eb76bb8c7fea2ca29a8",
                bundle_file = "#{@tmp_path}/my_bundle-957e59b82bd39eb76bb8c7fea2ca29a8.js",
                source_map_file = "#{@tmp_path}/my_bundle-957e59b82bd39eb76bb8c7fea2ca29a8.js.map"}

      assert File.read!(bundle_file) == """
             (()=>{})();
             //# sourceMappingURL=my_bundle-957e59b82bd39eb76bb8c7fea2ca29a8.js.map
             """

      assert File.read!(source_map_file) == """
             {
               "version": 3,
               "sources": [],
               "sourcesContent": [],
               "mappings": "",
               "names": []
             }
             """
    end
  end

  describe "diff_module_digest_plts/2" do
    setup do
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

      [result: diff_module_digest_plts(old_plt, new_plt)]
    end

    test "added modules", %{result: result} do
      assert %{added_modules: [:module_2, :module_4]} = result
    end

    test "removed modules", %{result: result} do
      assert %{removed_modules: [:module_5, :module_7]} = result
    end

    test "updated modules", %{result: result} do
      assert %{updated_modules: [:module_3, :module_6]} = result
    end
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

  test "install_js_deps/1" do
    assert install_js_deps(@assets_dir) == :ok
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

    sorted_mfas =
      call_graph
      |> list_page_mfas(Module5)
      |> Enum.sort()

    assert sorted_mfas == [
             {Module5, :__layout_module__, 0},
             {Module5, :__layout_props__, 0},
             {Module5, :__route__, 0},
             {Module5, :action, 3},
             {Module5, :template, 0},
             {Module6, :action, 3},
             {Module6, :template, 0},
             {Module7, :my_fun_7a, 2}
           ]
  end

  describe "list_runtime_mfas/1" do
    setup do
      diff = %{
        added_modules: Reflection.list_std_lib_elixir_modules(),
        removed_modules: [],
        updated_modules: []
      }

      ir_plt = PLT.start()
      patch_ir_plt(ir_plt, diff)

      call_graph = CallGraph.start()
      CallGraph.patch(call_graph, ir_plt, diff)

      [call_graph: call_graph, mfas: list_runtime_mfas(call_graph)]
    end

    test "includes MFAs that are reachable by Elixir functions used by the runtime", %{mfas: mfas} do
      assert {Enum, :into, 2} in mfas
      assert {Enum, :into_protocol, 2} in mfas
      assert {:lists, :foldl, 3} in mfas

      assert {Enum, :to_list, 1} in mfas
      assert {Enum, :reverse, 1} in mfas
      assert {:lists, :reverse, 1} in mfas

      assert {Kernel, :inspect, 2} in mfas
      assert {Inspect.Opts, :new, 1} in mfas
      assert {:binary, :copy, 2} in mfas
    end

    test "includes MFAs that are reachable by Erlang functions used by the runtime", %{mfas: mfas} do
      assert {:erlang, :==, 2} in mfas
      assert {:erlang, :error, 2} in mfas
    end

    test "removes duplicates", %{mfas: mfas} do
      count = Enum.count(mfas, &(&1 == {Access, :get, 2}))
      assert count == 1
    end

    test "removes MFAs with non-existing modules", %{call_graph: call_graph} do
      call_graph
      |> CallGraph.add_edge({Enum, :into, 2}, {Calendar.ISO, :dummy_function_1, 1})
      |> CallGraph.add_edge({Enum, :into, 2}, {NonExistingModuleFixture, :dummy_function_2, 2})
      |> CallGraph.add_edge({Enum, :into, 2}, {:maps, :dummy_function_3, 3})
      |> CallGraph.add_edge(
        {Enum, :into, 2},
        {:non_existing_module_fixture, :dummy_function_4, 4}
      )

      mfas = list_runtime_mfas(call_graph)

      assert {Calendar.ISO, :dummy_function_1, 1} in mfas
      refute {NonExistingModuleFixture, :dummy_function_2, 2} in mfas
      assert {:maps, :dummy_function_3, 3} in mfas
      refute {:non_existing_module_fixture, :dummy_function_4, 4} in mfas
    end

    test "sorts results", %{mfas: mfas} do
      assert hd(mfas) == {Access, :get, 2}
    end
  end

  describe "patch_ir_plt/2" do
    setup do
      plt =
        PLT.start()
        |> PLT.put(:module_5, :ir_5)
        |> PLT.put(:module_6, :ir_6)
        |> PLT.put(Module3, :ir_3)
        |> PLT.put(:module_7, :ir_7)
        |> PLT.put(:module_8, :ir_8)
        |> PLT.put(Module4, :ir_4)

      diff = %{
        added_modules: [Module1, Module2],
        removed_modules: [:module_5, :module_7],
        updated_modules: [Module3, Module4]
      }

      patch_ir_plt(plt, diff)

      [plt: plt]
    end

    test "adds entries of added modules", %{plt: plt} do
      assert PLT.get(plt, Module1) ==
               {:ok,
                %IR.ModuleDefinition{
                  module: %IR.AtomType{
                    value: Module1
                  },
                  body: %IR.Block{expressions: []}
                }}

      assert PLT.get(plt, Module2) ==
               {:ok,
                %IR.ModuleDefinition{
                  module: %IR.AtomType{
                    value: Module2
                  },
                  body: %IR.Block{expressions: []}
                }}
    end

    test "removes entries of removed modules", %{plt: plt} do
      assert PLT.get(plt, :module_5) == :error
      assert PLT.get(plt, :module_7) == :error
    end

    test "updates entries of updated modules", %{plt: plt} do
      assert PLT.get(plt, Module3) ==
               {:ok,
                %IR.ModuleDefinition{
                  module: %IR.AtomType{
                    value: Module3
                  },
                  body: %IR.Block{expressions: []}
                }}

      assert PLT.get(plt, Module4) ==
               {:ok,
                %IR.ModuleDefinition{
                  module: %IR.AtomType{
                    value: Module4
                  },
                  body: %IR.Block{expressions: []}
                }}
    end

    test "doesn't change entries of unchanged modules", %{plt: plt} do
      assert PLT.get(plt, :module_6) == {:ok, :ir_6}
      assert PLT.get(plt, :module_8) == {:ok, :ir_8}
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
end
