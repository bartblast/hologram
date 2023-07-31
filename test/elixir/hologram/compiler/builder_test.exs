defmodule Hologram.Compiler.BuilderTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Builder

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.IR

  alias Hologram.Test.Fixtures.Compiler.Builder.Module1
  alias Hologram.Test.Fixtures.Compiler.Builder.Module10
  alias Hologram.Test.Fixtures.Compiler.Builder.Module2
  alias Hologram.Test.Fixtures.Compiler.Builder.Module3
  alias Hologram.Test.Fixtures.Compiler.Builder.Module4
  alias Hologram.Test.Fixtures.Compiler.Builder.Module5
  alias Hologram.Test.Fixtures.Compiler.Builder.Module6
  alias Hologram.Test.Fixtures.Compiler.Builder.Module7
  alias Hologram.Test.Fixtures.Compiler.Builder.Module8
  alias Hologram.Test.Fixtures.Compiler.Builder.Module9

  @call_graph_name_1 :"call_graph_{__MODULE__}_1"
  @call_graph_name_2 :"call_graph_{__MODULE__}_2"
  @plt_name_1 :"plt_#{__MODULE__}_1"
  @plt_name_2 :"plt_#{__MODULE__}_2"

  setup do
    wait_for_plt_cleanup(@plt_name_1)
    wait_for_plt_cleanup(@plt_name_2)
    :ok
  end

  test "build_entry_page_js/3" do
    module_8_ir = IR.for_module(Module8)
    module_9_ir = IR.for_module(Module9)
    module_10_ir = IR.for_module(Module10)

    call_graph =
      [name: @call_graph_name_1]
      |> CallGraph.start()
      |> CallGraph.build(module_8_ir)
      |> CallGraph.build(module_9_ir)
      |> CallGraph.build(module_10_ir)

    ir_plt =
      [name: @plt_name_1]
      |> PLT.start()
      |> PLT.put(Module8, module_8_ir)
      |> PLT.put(Module9, module_9_ir)
      |> PLT.put(Module10, module_10_ir)

    assert build_entry_page_js(call_graph, ir_plt, Module9) == """
           window.__hologramPageReachableFunctionDefs__ = (interpreterClass, typeClass) => {
             const Interpreter = interpreterClass;
             const Type = typeClass;

           Interpreter.defineFunction("Elixir_Hologram_Test_Fixtures_Compiler_Builder_Module10", "action", [{params: [Type.atom("action_10a"), Type.variablePattern("params"), Type.variablePattern("state")], guard: null, body: (vars) => {
           return .fun_10a(vars.params, vars.state);
           }}])

           Interpreter.defineFunction("Elixir_Hologram_Test_Fixtures_Compiler_Builder_Module10", "fun_10a", [{params: [Type.variablePattern("params"), Type.variablePattern("state")], guard: null, body: (vars) => {
           return Type.tuple([vars.params, vars.state]);
           }}])

           Interpreter.defineFunction("Elixir_Hologram_Test_Fixtures_Compiler_Builder_Module10", "template", [{params: [], guard: null, body: (vars) => {
           return Type.anonymousFunction(1, [{params: [Type.variablePattern("data")], guard: null, body: (vars) => {
           return {
           Interpreter.matchOperator(vars.data, Type.matchPlaceholder(), vars);
           return Type.list([Type.tuple([Type.atom("text"), Type.bitstring("Module10 template")])]);
           };
           }}], vars);
           }}])

           Interpreter.defineFunction("Elixir_Hologram_Test_Fixtures_Compiler_Builder_Module9", "__hologram_layout_module__", [{params: [], guard: null, body: (vars) => {
           return Type.atom("Elixir.Hologram.Test.Fixtures.Compiler.Builder.Module10");
           }}])

           Interpreter.defineFunction("Elixir_Hologram_Test_Fixtures_Compiler_Builder_Module9", "__hologram_layout_props__", [{params: [], guard: null, body: (vars) => {
           return Type.list([]);
           }}])

           Interpreter.defineFunction("Elixir_Hologram_Test_Fixtures_Compiler_Builder_Module9", "__hologram_route__", [{params: [], guard: null, body: (vars) => {
           return Type.bitstring("/my_path");
           }}])

           Interpreter.defineFunction("Elixir_Hologram_Test_Fixtures_Compiler_Builder_Module9", "action", [{params: [Type.atom("action_9a"), Type.variablePattern("params"), Type.variablePattern("state")], guard: null, body: (vars) => {
           return .fun_9a(vars.params, vars.state);
           }}])

           Interpreter.defineFunction("Elixir_Hologram_Test_Fixtures_Compiler_Builder_Module9", "fun_9a", [{params: [Type.variablePattern("params"), Type.variablePattern("state")], guard: null, body: (vars) => {
           return Type.tuple([vars.params, vars.state]);
           }}])

           Interpreter.defineFunction("Elixir_Hologram_Test_Fixtures_Compiler_Builder_Module9", "template", [{params: [], guard: null, body: (vars) => {
           return Type.anonymousFunction(1, [{params: [Type.variablePattern("data")], guard: null, body: (vars) => {
           return {
           Interpreter.matchOperator(vars.data, Type.matchPlaceholder(), vars);
           return Type.list([Type.tuple([Type.atom("text"), Type.bitstring("Module9 template")])]);
           };
           }}], vars);
           }}])

           }\
           """
  end

  test "build_module_digest_plt/1" do
    assert %PLT{name: @plt_name_1} = plt = build_module_digest_plt(@plt_name_1)

    assert {:ok, <<_digest::256>>} = PLT.get(plt, Hologram.Compiler.Builder)
  end

  test "build_runtime_js/3" do
    # setup
    clean_tmp_dir()
    install_lib_js_deps()

    assert {digest, output_path, source_map_path} =
             build_runtime_js("assets/node_modules/esbuild", "assets/js/hologram.mjs", "tmp")

    assert digest =~ ~r/^[0-9a-f]{32}$/
    assert output_path == "tmp/hologram.runtime-#{digest}.js"
    assert source_map_path == "tmp/hologram.runtime-#{digest}.js.map"

    output_js = File.read!(output_path)
    assert String.starts_with?(output_js, ~s("use strict"))

    assert String.ends_with?(
             output_js,
             "//# sourceMappingURL=hologram.runtime-#{digest}.js.map\n"
           )

    source_map_json = File.read!(source_map_path)
    assert String.starts_with?(source_map_json, ~s({\n  "version": 3,\n  "sources": ["))
  end

  describe "diff_module_digest_plts/2" do
    setup do
      old_plt =
        [name: @plt_name_1]
        |> PLT.start()
        |> PLT.put(:module_1, :digest_1)
        |> PLT.put(:module_3, :digest_3a)
        |> PLT.put(:module_5, :digest_5)
        |> PLT.put(:module_6, :digest_6a)
        |> PLT.put(:module_7, :digest_7)

      new_plt =
        [name: @plt_name_2]
        |> PLT.start()
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

  test "entry_page_reachable_mfas/3" do
    module_5_ir = IR.for_module(Module5)
    module_6_ir = IR.for_module(Module6)
    module_7_ir = IR.for_module(Module7)

    call_graph =
      [name: @call_graph_name_1]
      |> CallGraph.start()
      |> CallGraph.build(module_5_ir)
      |> CallGraph.build(module_6_ir)
      |> CallGraph.build(module_7_ir)

    sorted_reachable_mfas =
      call_graph
      |> entry_page_reachable_mfas(Module5, @call_graph_name_2)
      |> Enum.sort()

    assert sorted_reachable_mfas == [
             {Module5, :__hologram_layout_module__, 0},
             {Module5, :__hologram_layout_props__, 0},
             {Module5, :__hologram_route__, 0},
             {Module5, :action, 3},
             {Module5, :template, 0},
             {Module6, :action, 3},
             {Module6, :template, 0},
             {Module7, :my_fun_7a, 2}
           ]
  end

  test "group_mfas/1" do
    mfas = [
      {:module_1, :fun_a, 1},
      {:module_2, :fun_b, 2},
      {:module_3, :fun_c, 3},
      {:module_1, :fun_d, 3},
      {:module_2, :fun_e, 1},
      {:module_3, :fun_f, 2}
    ]

    assert group_mfas(mfas) == %{
             module_1: [{:module_1, :fun_a, 1}, {:module_1, :fun_d, 3}],
             module_2: [{:module_2, :fun_b, 2}, {:module_2, :fun_e, 1}],
             module_3: [{:module_3, :fun_c, 3}, {:module_3, :fun_f, 2}]
           }
  end

  describe "patch_ir_plt/2" do
    setup do
      plt =
        [name: @plt_name_1]
        |> PLT.start()
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
                     guard: nil,
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
                     guard: nil,
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
                     guard: nil,
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
