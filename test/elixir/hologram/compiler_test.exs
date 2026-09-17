defmodule Hologram.CompilerTest do
  use Hologram.Test.BasicCase, async: false
  import Hologram.Compiler

  alias Hologram.Commons.PLT
  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Digraph
  alias Hologram.Compiler.Encoder
  alias Hologram.Compiler.IR
  alias Hologram.Reflection

  alias Hologram.Test.Fixtures.Compiler.Module1
  alias Hologram.Test.Fixtures.Compiler.Module11
  alias Hologram.Test.Fixtures.Compiler.Module12
  alias Hologram.Test.Fixtures.Compiler.Module13
  alias Hologram.Test.Fixtures.Compiler.Module14
  alias Hologram.Test.Fixtures.Compiler.Module15
  alias Hologram.Test.Fixtures.Compiler.Module17
  alias Hologram.Test.Fixtures.Compiler.Module18
  alias Hologram.Test.Fixtures.Compiler.Module19
  alias Hologram.Test.Fixtures.Compiler.Module2
  alias Hologram.Test.Fixtures.Compiler.Module21
  alias Hologram.Test.Fixtures.Compiler.Module22
  alias Hologram.Test.Fixtures.Compiler.Module23
  alias Hologram.Test.Fixtures.Compiler.Module24
  alias Hologram.Test.Fixtures.Compiler.Module25
  alias Hologram.Test.Fixtures.Compiler.Module26
  alias Hologram.Test.Fixtures.Compiler.Module27
  alias Hologram.Test.Fixtures.Compiler.Module28
  alias Hologram.Test.Fixtures.Compiler.Module29
  alias Hologram.Test.Fixtures.Compiler.Module3
  alias Hologram.Test.Fixtures.Compiler.Module30
  alias Hologram.Test.Fixtures.Compiler.Module32
  alias Hologram.Test.Fixtures.Compiler.Module34
  alias Hologram.Test.Fixtures.Compiler.Module36
  alias Hologram.Test.Fixtures.Compiler.Module37
  alias Hologram.Test.Fixtures.Compiler.Module38
  alias Hologram.Test.Fixtures.Compiler.Module4
  alias Hologram.Test.Fixtures.Compiler.Module40
  alias Hologram.Test.Fixtures.Compiler.Module8
  alias Hologram.Test.Fixtures.Compiler.Module9

  @root_dir Reflection.root_dir()
  @assets_dir Path.join(@root_dir, "assets")
  @js_dir Path.join(@assets_dir, "js")
  @erlang_js_dir Path.join(@js_dir, "erlang")

  @fixtures_compiler_dir Path.join(@fixtures_dir, "compiler")
  @tmp_dir Reflection.tmp_dir()

  # Runs the function with call counts on the one-argument protocol and JS import checks, which
  # consult a module's code path, and returns its result with the number of such checks.
  defp count_module_self_checks(fun) do
    mfas = [{Reflection, :protocol?, 1}, {Reflection, :js_imports?, 1}]
    Enum.each(mfas, &:erlang.trace_pattern(&1, true, [:call_count]))

    try do
      result = fun.()

      count =
        mfas
        |> Enum.map(fn mfa ->
          {:call_count, count} = :erlang.trace_info(mfa, :call_count)
          count
        end)
        |> Enum.sum()

      {result, count}
    after
      Enum.each(mfas, &:erlang.trace_pattern(&1, false, [:call_count]))
    end
  end

  # validate_prop_usages/2 walks a module's template/0, so hand-built DOM IR has to be wrapped the way
  # a compiled module carries it. Built by hand rather than taken from a fixture module, because a
  # fixture with a deliberately invalid usage would fail the compile.hologram Mix task tests.
  defp module_ir_with_template(dom_ir) do
    # The module field is left unset - the message names the module validate_prop_usages/2 was given,
    # not the one recorded in the IR.
    %IR.ModuleDefinition{
      body: %IR.Block{
        expressions: [
          %IR.FunctionDefinition{
            name: :template,
            arity: 0,
            visibility: :public,
            clause: %IR.FunctionClause{
              params: [],
              guards: [],
              body: %IR.Block{expressions: [dom_ir]}
            }
          }
        ]
      }
    }
  end

  defp setup_js_deps_test(test_subdir) do
    test_tmp_dir = Path.join([@tmp_dir, "tests", "compiler", test_subdir])
    assets_dir = Path.join(test_tmp_dir, "assets")
    build_dir = Path.join(test_tmp_dir, "build")

    clean_dir(test_tmp_dir)
    File.mkdir_p!(assets_dir)
    File.mkdir_p!(build_dir)

    lib_package_json_path = Path.join(@assets_dir, "package.json")
    fixture_package_json_path = Path.join(assets_dir, "package.json")
    File.cp!(lib_package_json_path, fixture_package_json_path)

    [assets_dir: assets_dir, build_dir: build_dir]
  end

  setup_all do
    ir_plt = build_ir_plt()
    call_graph = build_call_graph(ir_plt)

    [
      call_graph: call_graph,
      ir_plt: ir_plt,
      module_info_plt: CallGraph.module_info_plt(call_graph),
      runtime_mfas: CallGraph.list_runtime_mfas(call_graph, Reflection.list_pages())
    ]
  end

  describe "aggregate_js_imports/4" do
    test "empty MFAs list", %{ir_plt: ir_plt, module_info_plt: module_info_plt} do
      assert aggregate_js_imports([], ir_plt, module_info_plt) == %{imports: [], bindings: %{}}
    end

    test "filters out Erlang modules", %{ir_plt: ir_plt, module_info_plt: module_info_plt} do
      mfas = [{:erlang, :+, 2}, {:maps, :get, 2}]

      assert aggregate_js_imports(mfas, ir_plt, module_info_plt) == %{imports: [], bindings: %{}}
    end

    test "no modules have JS imports", %{ir_plt: ir_plt, module_info_plt: module_info_plt} do
      mfas = [{Enum, :map, 2}, {Kernel, :+, 2}]

      assert aggregate_js_imports(mfas, ir_plt, module_info_plt) == %{imports: [], bindings: %{}}
    end

    test "skips modules that use Hologram.JS but have no imports", %{
      ir_plt: ir_plt,
      module_info_plt: module_info_plt
    } do
      mfas = [{Module13, :func, 0}]

      assert aggregate_js_imports(mfas, ir_plt, module_info_plt) == %{imports: [], bindings: %{}}
    end

    test "single module with imports", %{ir_plt: ir_plt, module_info_plt: module_info_plt} do
      mfas = [{Module12, :func, 0}, {Enum, :map, 2}]

      assert aggregate_js_imports(mfas, ir_plt, module_info_plt) == %{
               imports: [
                 %{from: "chart.js", export: "Chart", alias: "$1"},
                 %{from: "chart.js", export: "helpers", alias: "$2"}
               ],
               bindings: %{
                 Module12 => %{
                   "MyChart" => "$1",
                   "helpers" => "$2"
                 }
               }
             }
    end

    test "multiple modules with imports from different sources", %{
      ir_plt: ir_plt,
      module_info_plt: module_info_plt
    } do
      mfas = [{Module12, :func, 0}, {Module17, :func, 0}]

      assert aggregate_js_imports(mfas, ir_plt, module_info_plt) == %{
               imports: [
                 %{from: "chart.js", export: "Chart", alias: "$1"},
                 %{from: "chart.js", export: "helpers", alias: "$2"},
                 %{from: "utils.js", export: "formatDate", alias: "$3"}
               ],
               bindings: %{
                 Module12 => %{
                   "MyChart" => "$1",
                   "helpers" => "$2"
                 },
                 Module17 => %{
                   "myFormatDate" => "$3"
                 }
               }
             }
    end

    test "deduplicates modules when multiple MFAs reference the same module", %{
      ir_plt: ir_plt,
      module_info_plt: module_info_plt
    } do
      mfas = [{Module12, :func_a, 0}, {Module12, :func_b, 1}]

      assert aggregate_js_imports(mfas, ir_plt, module_info_plt) == %{
               imports: [
                 %{from: "chart.js", export: "Chart", alias: "$1"},
                 %{from: "chart.js", export: "helpers", alias: "$2"}
               ],
               bindings: %{
                 Module12 => %{
                   "MyChart" => "$1",
                   "helpers" => "$2"
                 }
               }
             }
    end

    test "deduplicates imports when multiple modules import the same export", %{
      ir_plt: ir_plt,
      module_info_plt: module_info_plt
    } do
      mfas = [{Module14, :func, 0}, {Module15, :func, 0}]

      assert aggregate_js_imports(mfas, ir_plt, module_info_plt) == %{
               imports: [
                 %{from: "chart.js", export: "Chart", alias: "$1"}
               ],
               bindings: %{
                 Module14 => %{
                   "Chart" => "$1"
                 },
                 Module15 => %{
                   "MyChart" => "$1"
                 }
               }
             }
    end

    test "skips excluded modules", %{ir_plt: ir_plt, module_info_plt: module_info_plt} do
      mfas = [{Module14, :func, 0}, {Module15, :func, 0}]

      assert aggregate_js_imports(mfas, ir_plt, module_info_plt, MapSet.new([Module14])) == %{
               imports: [
                 %{from: "chart.js", export: "Chart", alias: "$1"}
               ],
               bindings: %{
                 Module15 => %{
                   "MyChart" => "$1"
                 }
               }
             }
    end

    test "skips the imports of a module that is excluded", %{
      ir_plt: ir_plt,
      module_info_plt: module_info_plt
    } do
      mfas = [{Module12, :func, 0}]

      assert aggregate_js_imports(mfas, ir_plt, module_info_plt, MapSet.new([Module12])) == %{
               imports: [],
               bindings: %{}
             }
    end

    test "a nil module info PLT asks every module", %{
      ir_plt: ir_plt,
      module_info_plt: module_info_plt
    } do
      mfas = [{Module12, :func, 0}, {Enum, :map, 2}]

      assert aggregate_js_imports(mfas, ir_plt, nil) ==
               aggregate_js_imports(mfas, ir_plt, module_info_plt)
    end
  end

  describe "build_page_js/5" do
    setup %{call_graph: call_graph, runtime_mfas: runtime_mfas} do
      call_graph_without_runtime_mfas =
        call_graph
        |> CallGraph.clone()
        |> CallGraph.remove_runtime_mfas!(runtime_mfas)

      graph = CallGraph.get_graph(call_graph_without_runtime_mfas)
      templatables = Reflection.list_pages() ++ Reflection.list_components()

      server_callback_analysis_by_templatable =
        CallGraph.server_callback_analysis_by_templatable(
          graph,
          templatables,
          CallGraph.module_info_plt(call_graph)
        )

      # A PLT per test, so one test's warm cache can never stand in for another's encoding.
      [
        encode_plt: PLT.start(),
        graph: graph,
        module_info_plt: CallGraph.module_info_plt(call_graph),
        server_callback_analysis_by_templatable: server_callback_analysis_by_templatable
      ]
    end

    test "has both Erlang and Elixir function defs", %{
      encode_plt: encode_plt,
      graph: graph,
      ir_plt: ir_plt,
      module_info_plt: module_info_plt,
      server_callback_analysis_by_templatable: server_callback_analysis_by_templatable
    } do
      mfas =
        CallGraph.list_page_mfas(
          graph,
          Module24,
          server_callback_analysis_by_templatable,
          module_info_plt
        )

      result =
        build_page_js(
          mfas,
          ir_plt,
          encode_plt,
          MapSet.new(),
          js_dir: @js_dir
        )

      js_fragment_1 = ~s/globalThis.Hologram.pageReachableFunctionDefs/
      js_fragment_2 = ~s/Interpreter.defineElixirFunction/
      js_fragment_3 = ~s/Interpreter.defineErlangFunction/

      assert String.contains?(result, js_fragment_1)
      assert String.contains?(result, js_fragment_2)
      assert String.contains?(result, js_fragment_3)
    end

    test "has only Elixir defs", %{
      encode_plt: encode_plt,
      graph: graph,
      ir_plt: ir_plt,
      module_info_plt: module_info_plt,
      server_callback_analysis_by_templatable: server_callback_analysis_by_templatable
    } do
      mfas =
        CallGraph.list_page_mfas(
          graph,
          Module25,
          server_callback_analysis_by_templatable,
          module_info_plt
        )

      result =
        build_page_js(
          mfas,
          ir_plt,
          encode_plt,
          MapSet.new(),
          js_dir: @js_dir
        )

      js_fragment_1 = ~s/globalThis.Hologram.pageReachableFunctionDefs/
      js_fragment_2 = ~s/Interpreter.defineElixirFunction/
      js_fragment_3 = ~s/Interpreter.defineErlangFunction/

      assert String.contains?(result, js_fragment_1)
      assert String.contains?(result, js_fragment_2)
      refute String.contains?(result, js_fragment_3)
    end

    test "no JS imports", %{
      encode_plt: encode_plt,
      graph: graph,
      ir_plt: ir_plt,
      module_info_plt: module_info_plt,
      server_callback_analysis_by_templatable: server_callback_analysis_by_templatable
    } do
      mfas =
        CallGraph.list_page_mfas(
          graph,
          Module11,
          server_callback_analysis_by_templatable,
          module_info_plt
        )

      result =
        build_page_js(
          mfas,
          ir_plt,
          encode_plt,
          MapSet.new(),
          js_dir: @js_dir
        )

      refute String.contains?(result, "import {")
      refute String.contains?(result, "registerJsBindings")
    end

    test "single JS import", %{
      encode_plt: encode_plt,
      graph: graph,
      ir_plt: ir_plt,
      module_info_plt: module_info_plt,
      server_callback_analysis_by_templatable: server_callback_analysis_by_templatable
    } do
      mfas =
        CallGraph.list_page_mfas(
          graph,
          Module19,
          server_callback_analysis_by_templatable,
          module_info_plt
        )

      result =
        build_page_js(
          mfas,
          ir_plt,
          encode_plt,
          MapSet.new(),
          js_dir: @js_dir
        )

      js_fixture_path = Path.join([@fixtures_dir, "compiler", "js_fixture_1.mjs"])

      assert length(Regex.scan(~r/import \{/, result)) == 1
      assert String.contains?(result, ~s'import { export_1a as $1 } from "#{js_fixture_path}";')

      assert length(Regex.scan(~r/registerJsBindings/, result)) == 1

      assert String.contains?(
               result,
               ~s'Interpreter.registerJsBindings({"Hologram.Test.Fixtures.Compiler.Module18": {"alias_1a": $1}});'
             )
    end

    test "multiple JS imports", %{
      encode_plt: encode_plt,
      graph: graph,
      ir_plt: ir_plt,
      module_info_plt: module_info_plt,
      server_callback_analysis_by_templatable: server_callback_analysis_by_templatable
    } do
      mfas =
        CallGraph.list_page_mfas(
          graph,
          Module21,
          server_callback_analysis_by_templatable,
          module_info_plt
        )

      result =
        build_page_js(
          mfas,
          ir_plt,
          encode_plt,
          MapSet.new(),
          js_dir: @js_dir
        )

      js_fixture_path = Path.join([@fixtures_dir, "compiler", "js_fixture_1.mjs"])

      assert length(Regex.scan(~r/import \{/, result)) == 2
      assert String.contains?(result, ~s'import { export_1a as $1 } from "#{js_fixture_path}";')
      assert String.contains?(result, ~s'import { export_1b as $2 } from "#{js_fixture_path}";')

      assert length(Regex.scan(~r/registerJsBindings/, result)) == 1

      assert String.contains?(
               result,
               ~s'Interpreter.registerJsBindings({"Hologram.Test.Fixtures.Compiler.Module20": {"alias_1a": $1, "alias_1b": $2}});'
             )
    end

    test "multiple modules with JS imports", %{
      encode_plt: encode_plt,
      graph: graph,
      ir_plt: ir_plt,
      module_info_plt: module_info_plt,
      server_callback_analysis_by_templatable: server_callback_analysis_by_templatable
    } do
      mfas =
        CallGraph.list_page_mfas(
          graph,
          Module23,
          server_callback_analysis_by_templatable,
          module_info_plt
        )

      result =
        build_page_js(
          mfas,
          ir_plt,
          encode_plt,
          MapSet.new(),
          js_dir: @js_dir
        )

      js_fixture_1_path = Path.join([@fixtures_dir, "compiler", "js_fixture_1.mjs"])
      js_fixture_2_path = Path.join([@fixtures_dir, "compiler", "js_fixture_2.mjs"])

      assert length(Regex.scan(~r/import \{/, result)) == 2
      assert String.contains?(result, ~s'import { export_1a as $1 } from "#{js_fixture_1_path}";')
      assert String.contains?(result, ~s'import { export_2 as $2 } from "#{js_fixture_2_path}";')

      assert length(Regex.scan(~r/registerJsBindings/, result)) == 1

      assert String.contains?(
               result,
               ~s'Interpreter.registerJsBindings({"Hologram.Test.Fixtures.Compiler.Module18": {"alias_1a": $1}, "Hologram.Test.Fixtures.Compiler.Module22": {"alias_2": $2}});'
             )
    end

    test "skips the JS imports of the modules the runtime script registers", %{
      encode_plt: encode_plt,
      graph: graph,
      ir_plt: ir_plt,
      module_info_plt: module_info_plt,
      server_callback_analysis_by_templatable: server_callback_analysis_by_templatable
    } do
      mfas =
        CallGraph.list_page_mfas(
          graph,
          Module23,
          server_callback_analysis_by_templatable,
          module_info_plt
        )

      result =
        build_page_js(
          mfas,
          ir_plt,
          encode_plt,
          MapSet.new(),
          js_dir: @js_dir,
          runtime_js_binding_modules: MapSet.new([Module18])
        )

      js_fixture_1_path = Path.join([@fixtures_dir, "compiler", "js_fixture_1.mjs"])
      js_fixture_2_path = Path.join([@fixtures_dir, "compiler", "js_fixture_2.mjs"])

      assert length(Regex.scan(~r/import \{/, result)) == 1
      assert String.contains?(result, ~s'import { export_2 as $1 } from "#{js_fixture_2_path}";')

      assert String.contains?(
               result,
               ~s'Interpreter.registerJsBindings({"Hologram.Test.Fixtures.Compiler.Module22": {"alias_2": $1}});'
             )

      # The excluded module's function defs still belong to this bundle - only its bindings,
      # and therefore the JavaScript module they come from, are left to the runtime script.
      refute String.contains?(result, js_fixture_1_path)

      assert String.contains?(
               result,
               ~s/Interpreter.defineElixirFunction("Hologram.Test.Fixtures.Compiler.Module18"/
             )
    end

    test "asks no module whether it is a protocol or declares JS imports when given the module info PLT",
         %{
           encode_plt: encode_plt,
           graph: graph,
           ir_plt: ir_plt,
           module_info_plt: module_info_plt,
           server_callback_analysis_by_templatable: server_callback_analysis_by_templatable
         } do
      mfas =
        CallGraph.list_page_mfas(
          graph,
          Module23,
          server_callback_analysis_by_templatable,
          module_info_plt
        )

      {without_plt, checks_without_plt} =
        count_module_self_checks(fn ->
          build_page_js(mfas, ir_plt, encode_plt, MapSet.new(), js_dir: @js_dir)
        end)

      {with_plt, checks_with_plt} =
        count_module_self_checks(fn ->
          build_page_js(mfas, ir_plt, encode_plt, MapSet.new(),
            js_dir: @js_dir,
            module_info_plt: module_info_plt
          )
        end)

      assert with_plt == without_plt
      assert checks_without_plt > 0
      assert checks_with_plt == 0
    end
  end

  test "build_call_graph/0" do
    assert %CallGraph{} = call_graph = build_call_graph()

    assert CallGraph.has_vertex?(call_graph, {Compiler, :build_call_graph, 1})
  end

  test "build_call_graph/2", %{ir_plt: ir_plt} do
    module_info_plt = PLT.put(PLT.start(), Module14, %{page?: true})

    assert %CallGraph{} = call_graph = build_call_graph(ir_plt, module_info_plt)
    assert CallGraph.module_info_plt(call_graph) == module_info_plt
    assert CallGraph.has_edge?(call_graph, Module14, {Module14, :__route__, 0})
  end

  describe "build_call_graph/1" do
    test "builds call graph from IR PLT", %{ir_plt: ir_plt} do
      assert %CallGraph{} = call_graph = build_call_graph(ir_plt)

      assert CallGraph.has_vertex?(call_graph, {Compiler, :build_call_graph, 1})
    end

    test "adds non-discoverable edges", %{ir_plt: ir_plt} do
      call_graph = build_call_graph(ir_plt)

      assert CallGraph.has_edge?(call_graph, {:binary, :match, 2}, {:binary, :match, 3})
      assert CallGraph.has_edge?(call_graph, {Date, :new, 4}, {Calendar.ISO, :valid_date?, 3})
    end
  end

  test "build_ir_plt/0" do
    assert %PLT{} = ir_plt = build_ir_plt()

    assert %IR.ModuleDefinition{module: %IR.AtomType{value: Hologram.Compiler}} =
             PLT.get!(ir_plt, Hologram.Compiler)
  end

  describe "build_ir_plt/1" do
    test "module has BEAM path" do
      assert %PLT{} = ir_plt = build_ir_plt()

      assert %IR.ModuleDefinition{module: %IR.AtomType{value: Hologram.Compiler}} =
               PLT.get!(ir_plt, Hologram.Compiler)
    end

    test "module doesn't have BEAM path" do
      assert %PLT{} = ir_plt = build_ir_plt()
      assert PLT.get(ir_plt, MyModule) == :error
    end

    test "builds IR for the given modules only" do
      assert %PLT{} = ir_plt = build_ir_plt(modules: [Module1])

      assert %IR.ModuleDefinition{} = PLT.get!(ir_plt, Module1)
      assert PLT.get(ir_plt, Hologram.Reflection) == :error
    end

    test "fills the given PLT" do
      plt = PLT.start()

      assert build_ir_plt(plt: plt, modules: [Module1]) == plt

      assert {:ok, %IR.ModuleDefinition{module: %IR.AtomType{value: Module1}}} =
               PLT.get(plt, Module1)

      PLT.stop(plt)
    end
  end

  describe "build_module_info_plt!/3" do
    test "adds an entry for every Elixir module that has a BEAM, none for the rest" do
      assert %PLT{} = plt = build_module_info_plt!(PLT.start(), nil)

      assert %{digest: digest, page?: false, component?: false} =
               PLT.get!(plt, Hologram.Reflection)

      assert is_integer(digest)
      assert PLT.get(plt, MyModule) == :error
      assert PLT.get(plt, Kernel.SpecialForms) == :error
    end

    test "marks pages and components" do
      plt = build_module_info_plt!(PLT.start(), nil)

      assert %{page?: true} = PLT.get!(plt, Hologram.Test.Fixtures.Reflection.Module2)
      assert %{component?: true} = PLT.get!(plt, Hologram.Test.Fixtures.Reflection.Module3)
    end

    test "entries match beam_info/1" do
      plt = build_module_info_plt!(PLT.start(), nil)
      beam_path = :code.which(Hologram.Reflection)

      assert PLT.get!(plt, Hologram.Reflection) == Reflection.beam_info(beam_path)
    end

    test "reuses the old entry when the BEAM is untouched and older than the dump" do
      beam_path = :code.which(Hologram.Reflection)
      %File.Stat{mtime: mtime} = File.stat!(beam_path, time: :posix)
      old_info = %{Reflection.beam_info(beam_path) | digest: 1, page?: true}
      old_plt = PLT.put(PLT.start(), Hologram.Reflection, old_info)

      plt = build_module_info_plt!(old_plt, mtime + 1)

      assert PLT.get!(plt, Hologram.Reflection) == old_info
    end

    test "reads the BEAM when it was written within a second of the dump" do
      beam_path = :code.which(Hologram.Reflection)
      %File.Stat{mtime: mtime, size: size} = File.stat!(beam_path, time: :posix)
      old_info = %{digest: 1, mtime: mtime, size: size, page?: true, component?: true}
      old_plt = PLT.put(PLT.start(), Hologram.Reflection, old_info)

      plt = build_module_info_plt!(old_plt, mtime)

      assert PLT.get!(plt, Hologram.Reflection) == Reflection.beam_info(beam_path)
    end

    test "reads the BEAM when its size differs from the old entry" do
      beam_path = :code.which(Hologram.Reflection)
      %File.Stat{mtime: mtime, size: size} = File.stat!(beam_path, time: :posix)
      old_info = %{digest: 1, mtime: mtime, size: size + 1, page?: true, component?: true}
      old_plt = PLT.put(PLT.start(), Hologram.Reflection, old_info)

      plt = build_module_info_plt!(old_plt, mtime + 1)

      assert PLT.get!(plt, Hologram.Reflection) == Reflection.beam_info(beam_path)
    end

    test "reads the BEAM when its mtime differs from the old entry" do
      beam_path = :code.which(Hologram.Reflection)
      %File.Stat{mtime: mtime, size: size} = File.stat!(beam_path, time: :posix)
      old_info = %{digest: 1, mtime: mtime - 1, size: size, page?: true, component?: true}
      old_plt = PLT.put(PLT.start(), Hologram.Reflection, old_info)

      plt = build_module_info_plt!(old_plt, mtime + 1)

      assert PLT.get!(plt, Hologram.Reflection) == Reflection.beam_info(beam_path)
    end

    test "reads the BEAM when the old entry lacks a key beam_info/1 returns now" do
      # The entry shape a dump written by an older Hologram holds. A path dependency or the
      # project itself keeps its build dir across Hologram changes, so such a dump can be read.
      beam_path = :code.which(Hologram.Reflection)
      %File.Stat{mtime: mtime, size: size} = File.stat!(beam_path, time: :posix)
      old_info = %{digest: 1, mtime: mtime, size: size, page?: true, component?: true}
      old_plt = PLT.put(PLT.start(), Hologram.Reflection, old_info)

      plt = build_module_info_plt!(old_plt, mtime + 1)

      assert PLT.get!(plt, Hologram.Reflection) == Reflection.beam_info(beam_path)
    end

    test "reads every BEAM when there is no previous dump" do
      beam_path = :code.which(Hologram.Reflection)
      %File.Stat{mtime: mtime, size: size} = File.stat!(beam_path, time: :posix)
      old_info = %{digest: 1, mtime: mtime, size: size, page?: true, component?: true}
      old_plt = PLT.put(PLT.start(), Hologram.Reflection, old_info)

      plt = build_module_info_plt!(old_plt, nil)

      assert PLT.get!(plt, Hologram.Reflection) == Reflection.beam_info(beam_path)
    end
  end

  describe "build_module_metadata/1" do
    test "maps each module with a source path to its application and relative source file" do
      module_info_plt =
        PLT.put(PLT.start(), [
          {Hologram.Reflection, %{source_path: Reflection.source_path(Hologram.Reflection)}},
          {Enum, %{source_path: Reflection.source_path(Enum)}}
        ])

      assert build_module_metadata(module_info_plt) == %{
               Enum => %{app: :elixir, file: "lib/enum.ex"},
               Hologram.Reflection => %{app: :hologram, file: "lib/hologram/reflection.ex"}
             }
    end

    test "leaves out a module without a source path" do
      module_info_plt = PLT.put(PLT.start(), Aaa.Bbb, %{source_path: nil})

      assert build_module_metadata(module_info_plt) == %{}
    end

    test "gives nil for the application of a module no loaded application lists" do
      module_info_plt = PLT.put(PLT.start(), Aaa.Bbb, %{source_path: "/elsewhere/aaa/bbb.ex"})

      assert build_module_metadata(module_info_plt) == %{Aaa.Bbb => %{app: nil, file: "bbb.ex"}}
    end
  end

  test "build_page_digest_plt/2" do
    build_dir = Path.join("/", "my_build_dir")
    opts = [build_dir: build_dir]

    bundle_info = [
      %{
        digest: "my-digest-1",
        entry_name: MyPage1
      },
      %{
        digest: "my-digest-2",
        entry_name: "runtime"
      },
      %{
        digest: "my-digest-3",
        entry_name: MyPage2
      }
    ]

    expected_page_digest_plt_dump_path =
      Path.join(build_dir, Reflection.page_digest_plt_dump_file_name())

    assert {%PLT{} = plt, ^expected_page_digest_plt_dump_path} =
             build_page_digest_plt(bundle_info, opts)

    assert PLT.get_all(plt) == %{MyPage1 => "my-digest-1", MyPage2 => "my-digest-3"}
  end

  describe "build_runtime_js/6" do
    setup do
      on_exit(fn ->
        Application.delete_env(:hologram, :client_error_overlay)
        Application.delete_env(:hologram, :client_stacktraces)
      end)

      # A PLT per test, so one test's warm cache can never stand in for another's encoding.
      [encode_plt: PLT.start()]
    end

    test "asks no module whether it is a protocol or declares JS imports when given the module info PLT",
         %{
           encode_plt: encode_plt,
           ir_plt: ir_plt,
           module_info_plt: module_info_plt,
           runtime_mfas: runtime_mfas
         } do
      # prune_module_def/2 still asks each rendered protocol module itself, on the protocol path.
      rendered_protocols =
        runtime_mfas
        |> Enum.map(fn {module, _function, _arity} -> module end)
        |> Enum.uniq()
        |> Enum.count(&Reflection.protocol?/1)

      {without_plt, checks_without_plt} =
        count_module_self_checks(fn ->
          build_runtime_js(runtime_mfas, ir_plt, encode_plt, MapSet.new(), [], js_dir: @js_dir)
        end)

      {with_plt, checks_with_plt} =
        count_module_self_checks(fn ->
          build_runtime_js(runtime_mfas, ir_plt, encode_plt, MapSet.new(), [],
            js_dir: @js_dir,
            module_info_plt: module_info_plt
          )
        end)

      assert with_plt == without_plt
      assert checks_without_plt > 0
      assert checks_with_plt == rendered_protocols
    end

    test "renders reachable function defs", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      js = build_runtime_js(runtime_mfas, ir_plt, encode_plt, MapSet.new(), [], js_dir: @js_dir)

      assert String.contains?(
               js,
               ~s/Interpreter.defineElixirFunction("Enum", "into", 2, "public"/
             )

      assert String.contains?(
               js,
               ~s/Interpreter.defineElixirFunction("Enum", "into_protocol", 2, "private"/
             )

      assert String.contains?(
               js,
               ~s/Interpreter.defineElixirFunction("String.Chars", "to_string", 1, "public"/
             )

      assert String.contains?(
               js,
               ~s/Interpreter.defineElixirFunction("String.Chars", "impl_for!", 1, "public"/
             )

      refute String.contains?(js, "Hologram.Test.Fixtures.Compiler.CallGraph.Module12")

      assert String.contains?(js, ~s/Interpreter.defineErlangFunction("erlang", "error", 1/)

      assert String.contains?(
               js,
               ~s/Interpreter.defineNotImplementedErlangFunction("erlang", "process_info", 2/
             )
    end

    test "encodes a function once and serves later calls from the encode PLT", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      js_1 = build_runtime_js(runtime_mfas, ir_plt, encode_plt, MapSet.new(), [], js_dir: @js_dir)

      assert {:ok, into_js} = PLT.get(encode_plt, {Enum, :into, 2})

      assert String.starts_with?(
               into_js,
               ~s/Interpreter.defineElixirFunction("Enum", "into", 2, "public"/
             )

      js_2 = build_runtime_js(runtime_mfas, ir_plt, encode_plt, MapSet.new(), [], js_dir: @js_dir)

      assert js_2 == js_1
    end

    test "a warm encode PLT is used instead of the module IR", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      js_1 = build_runtime_js(runtime_mfas, ir_plt, encode_plt, MapSet.new(), [], js_dir: @js_dir)

      # A clone, so the PLT shared by the whole test module keeps its Enum entry.
      ir_plt_without_enum =
        ir_plt
        |> PLT.clone()
        |> PLT.delete(Enum)

      js_2 =
        build_runtime_js(runtime_mfas, ir_plt_without_enum, encode_plt, MapSet.new(), [],
          js_dir: @js_dir
        )

      assert js_2 == js_1
    end

    test "remembers a reachable function the module does not define", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      undefined_mfa = {Enum, :hologram_undefined_fun, 9}

      js =
        build_runtime_js(
          [undefined_mfa | runtime_mfas],
          ir_plt,
          encode_plt,
          MapSet.new(),
          [],
          js_dir: @js_dir
        )

      expected_js =
        build_runtime_js(runtime_mfas, ir_plt, PLT.start(), MapSet.new(), [], js_dir: @js_dir)

      assert js == expected_js
      assert PLT.get(encode_plt, undefined_mfa) == {:ok, nil}
    end

    test "does not read the module IR again for a function the module does not define", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      mfas = [{Enum, :hologram_undefined_fun, 9} | runtime_mfas]

      js_1 = build_runtime_js(mfas, ir_plt, encode_plt, MapSet.new(), [], js_dir: @js_dir)

      # A clone, so the PLT shared by the whole test module keeps its Enum entry.
      ir_plt_without_enum =
        ir_plt
        |> PLT.clone()
        |> PLT.delete(Enum)

      js_2 =
        build_runtime_js(mfas, ir_plt_without_enum, encode_plt, MapSet.new(), [], js_dir: @js_dir)

      assert js_2 == js_1
    end

    test "protocol functions are rendered per entry file and not cached", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      js = build_runtime_js(runtime_mfas, ir_plt, encode_plt, MapSet.new(), [], js_dir: @js_dir)

      assert String.contains?(
               js,
               ~s/Interpreter.defineElixirFunction("String.Chars", "impl_for!", 1, "public"/
             )

      assert PLT.get(encode_plt, {String.Chars, :impl_for!, 1}) == :error
    end

    test "renders a module's functions ordered by name and arity", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      js = build_runtime_js(runtime_mfas, ir_plt, encode_plt, MapSet.new(), [], js_dir: @js_dir)

      {into_pos, _length} = :binary.match(js, ~s/defineElixirFunction("Enum", "into", 2/)

      {into_protocol_pos, _length} =
        :binary.match(js, ~s/defineElixirFunction("Enum", "into_protocol", 2/)

      assert into_pos < into_protocol_pos
    end

    test "renders the clause heads of manually ported functions", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      js = build_runtime_js(runtime_mfas, ir_plt, encode_plt, MapSet.new(), [], js_dir: @js_dir)

      assert String.contains?(
               js,
               ~s/Interpreter.defineFunctionClauseHeads("Code", "ensure_loaded", 1, "public", [{params: (context) => [Type.variablePattern("module_0")], guards: [(context) => Erlang["is_atom\/1"](context.vars.module_0)], blame: {params: ["module"], guards: [{source: "is_atom(module)", test: (context) => Erlang["is_atom\/1"](context.vars.module_0)}]}}]);/
             )

      # A default argument makes the ported arity differ from the raised one.
      assert String.contains?(
               js,
               ~s/Interpreter.defineFunctionClauseHeads("Task", "await", 2, "public"/
             )
    end

    test "injects the client config when the presentation settings are enabled", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      Application.put_env(:hologram, :client_error_overlay, true)
      Application.put_env(:hologram, :client_stacktraces, true)

      js = build_runtime_js(runtime_mfas, ir_plt, encode_plt, MapSet.new(), [], js_dir: @js_dir)

      assert String.contains?(
               js,
               "globalThis.Hologram.config = {errorOverlay: true, stacktraces: true};"
             )
    end

    test "injects the client config when the presentation settings are disabled", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      Application.put_env(:hologram, :client_error_overlay, false)
      Application.put_env(:hologram, :client_stacktraces, false)

      js = build_runtime_js(runtime_mfas, ir_plt, encode_plt, MapSet.new(), [], js_dir: @js_dir)

      assert String.contains?(
               js,
               "globalThis.Hologram.config = {errorOverlay: false, stacktraces: false};"
             )
    end

    test "registers the metadata of the modules it defines", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      Application.put_env(:hologram, :client_stacktraces, true)

      js = build_runtime_js(runtime_mfas, ir_plt, encode_plt, MapSet.new(), [], js_dir: @js_dir)

      assert String.contains?(
               js,
               ~s/ERTS.registerModuleMetadata({"Access": {app: "elixir", file: "lib\/access.ex"/
             )
    end

    test "injects the versions of the applications the frames name", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      Application.put_env(:hologram, :client_stacktraces, true)

      app_versions = [hologram: "0.1.0", my_app: "9.8.7"]

      js =
        build_runtime_js(runtime_mfas, ir_plt, encode_plt, MapSet.new(), app_versions,
          js_dir: @js_dir
        )

      assert String.contains?(
               js,
               ~s/ERTS.appVersions = {"hologram": "0.1.0", "my_app": "9.8.7"};/
             )
    end

    test "quotes an application name that isn't a JavaScript identifier", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      Application.put_env(:hologram, :client_stacktraces, true)

      app_versions = [{:"my-app", "9.8.7"}]

      js =
        build_runtime_js(runtime_mfas, ir_plt, encode_plt, MapSet.new(), app_versions,
          js_dir: @js_dir
        )

      assert String.contains?(js, ~s/ERTS.appVersions = {"my-app": "9.8.7"};/)
    end

    test "injects no application versions when client stacktraces are disabled", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      Application.put_env(:hologram, :client_stacktraces, false)

      app_versions = [hologram: "0.1.0", my_app: "9.8.7"]

      js =
        build_runtime_js(runtime_mfas, ir_plt, encode_plt, MapSet.new(), app_versions,
          js_dir: @js_dir
        )

      assert String.contains?(js, "ERTS.appVersions = {};")
    end

    test "injects the client config when the error overlay is opted out of", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      Application.put_env(:hologram, :client_error_overlay, false)
      Application.put_env(:hologram, :client_stacktraces, true)

      js = build_runtime_js(runtime_mfas, ir_plt, encode_plt, MapSet.new(), [], js_dir: @js_dir)

      assert String.contains?(
               js,
               "globalThis.Hologram.config = {errorOverlay: false, stacktraces: true};"
             )
    end

    test "no JS imports", %{encode_plt: encode_plt, ir_plt: ir_plt, runtime_mfas: runtime_mfas} do
      js = build_runtime_js(runtime_mfas, ir_plt, encode_plt, MapSet.new(), [], js_dir: @js_dir)

      refute String.contains?(js, "import {")
      refute String.contains?(js, "registerJsBindings")
    end

    test "JS imports of the modules it bundles", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      mfas = runtime_mfas ++ [{Module18, :my_fun, 0}, {Module22, :my_fun, 0}]

      js = build_runtime_js(mfas, ir_plt, encode_plt, MapSet.new(), [], js_dir: @js_dir)

      js_fixture_1_path = Path.join([@fixtures_dir, "compiler", "js_fixture_1.mjs"])
      js_fixture_2_path = Path.join([@fixtures_dir, "compiler", "js_fixture_2.mjs"])

      assert length(Regex.scan(~r/import \{/, js)) == 2
      assert String.contains?(js, ~s'import { export_1a as $1 } from "#{js_fixture_1_path}";')
      assert String.contains?(js, ~s'import { export_2 as $2 } from "#{js_fixture_2_path}";')

      assert length(Regex.scan(~r/registerJsBindings/, js)) == 1

      assert String.contains?(
               js,
               ~s'Interpreter.registerJsBindings({"Hologram.Test.Fixtures.Compiler.Module18": {"alias_1a": $1}, "Hologram.Test.Fixtures.Compiler.Module22": {"alias_2": $2}});'
             )
    end
  end

  test "bundle/2" do
    node_modules_path = Path.join([@root_dir, "assets", "node_modules"])
    tmp_dir = Path.join([Reflection.tmp_dir(), "tests", "compiler", "bundle_2"])

    opts = [
      esbuild_bin_path: Path.join([node_modules_path, ".bin", "esbuild"]),
      node_modules_path: node_modules_path,
      static_dir: Path.join(tmp_dir, "static"),
      tmp_dir: tmp_dir
    ]

    clean_dir(tmp_dir)
    File.mkdir!(opts[:static_dir])

    entry_file_path_1 = Path.join(tmp_dir, "MyPage.entry.js")
    File.write(entry_file_path_1, "export const myVar = 111;\n")

    entry_file_path_2 = Path.join(tmp_dir, "runtime.entry.js")
    File.write(entry_file_path_2, "export const myVar = 222;\n")

    entry_files_info = [
      {MyPage, entry_file_path_1, "page"},
      {"runtime", entry_file_path_2, "runtime"}
    ]

    expected_static_bundle_path_1 =
      Path.join(opts[:static_dir], "page-936cdd48d87d4ecd5720ad33b7fb4b7c.js")

    expected_static_source_map_path_1 = "#{expected_static_bundle_path_1}.map"

    expected_static_bundle_path_2 =
      Path.join(opts[:static_dir], "runtime-52169d07278b312ea39145c3b94c0203.js")

    expected_static_source_map_path_2 = "#{expected_static_bundle_path_2}.map"

    assert bundle(entry_files_info, opts) == [
             %{
               digest: "936cdd48d87d4ecd5720ad33b7fb4b7c",
               entry_name: MyPage,
               bundle_name: "page",
               static_bundle_path: expected_static_bundle_path_1,
               static_source_map_path: expected_static_source_map_path_1
             },
             %{
               digest: "52169d07278b312ea39145c3b94c0203",
               entry_name: "runtime",
               bundle_name: "runtime",
               static_bundle_path: expected_static_bundle_path_2,
               static_source_map_path: expected_static_source_map_path_2
             }
           ]

    expected_bundle_js_1 =
      normalize_newlines("""
      (()=>{var o=111;})();
      //# sourceMappingURL=page-936cdd48d87d4ecd5720ad33b7fb4b7c.js.map
      """)

    assert File.read!(expected_static_bundle_path_1) == expected_bundle_js_1

    expected_bundle_js_2 =
      normalize_newlines("""
      (()=>{var o=222;})();
      //# sourceMappingURL=runtime-52169d07278b312ea39145c3b94c0203.js.map
      """)

    assert File.read!(expected_static_bundle_path_2) == expected_bundle_js_2

    expected_source_map_js_1 =
      normalize_newlines("""
      {
        "version": 3,
        "sources": ["MyPage.entry.js"],
        "sourcesContent": ["export const myVar = 111;\\n"],
        "mappings": "MAAO,IAAMA,EAAQ",
        "names": ["myVar"]
      }
      """)

    assert File.read!(expected_static_source_map_path_1) == expected_source_map_js_1

    expected_source_map_js_2 =
      normalize_newlines("""
      {
        "version": 3,
        "sources": ["runtime.entry.js"],
        "sourcesContent": ["export const myVar = 222;\\n"],
        "mappings": "MAAO,IAAMA,EAAQ",
        "names": ["myVar"]
      }
      """)

    assert File.read!(expected_static_source_map_path_2) == expected_source_map_js_2
  end

  describe "bundle/4" do
    test "valid entry file" do
      node_modules_path = Path.join([@root_dir, "assets", "node_modules"])

      tmp_dir =
        Path.join([Reflection.tmp_dir(), "tests", "compiler", "bundle_4_valid_entry_file"])

      opts = [
        esbuild_bin_path: Path.join([node_modules_path, ".bin", "esbuild"]),
        node_modules_path: node_modules_path,
        static_dir: Path.join(tmp_dir, "static"),
        tmp_dir: tmp_dir
      ]

      clean_dir(tmp_dir)
      File.mkdir!(opts[:static_dir])

      entry_file_path = Path.join(tmp_dir, "MyPage.entry.js")
      File.write(entry_file_path, "export const myVar = 123;\n")

      expected_static_bundle_path =
        Path.join(opts[:static_dir], "my_bundle_name-76f1f092f95a34da067e35caad5e3317.js")

      expected_static_source_map_path = "#{expected_static_bundle_path}.map"

      assert bundle(MyPage, entry_file_path, "my_bundle_name", opts) == %{
               bundle_name: "my_bundle_name",
               digest: "76f1f092f95a34da067e35caad5e3317",
               entry_name: MyPage,
               static_bundle_path: expected_static_bundle_path,
               static_source_map_path: expected_static_source_map_path
             }

      expected_bundle_js =
        normalize_newlines("""
        (()=>{var o=123;})();
        //# sourceMappingURL=my_bundle_name-76f1f092f95a34da067e35caad5e3317.js.map
        """)

      assert File.read!(expected_static_bundle_path) == expected_bundle_js

      expected_source_map_js =
        normalize_newlines("""
        {
          "version": 3,
          "sources": ["MyPage.entry.js"],
          "sourcesContent": ["export const myVar = 123;\\n"],
          "mappings": "MAAO,IAAMA,EAAQ",
          "names": ["myVar"]
        }
        """)

      assert File.read!(expected_static_source_map_path) == expected_source_map_js
    end

    test "invalid entry file" do
      node_modules_path = Path.join([@root_dir, "assets", "node_modules"])

      tmp_dir =
        Path.join([Reflection.tmp_dir(), "tests", "compiler", "bundle_4_invalid_entry_file"])

      opts = [
        esbuild_bin_path: Path.join([node_modules_path, ".bin", "esbuild"]),
        node_modules_path: node_modules_path,
        static_dir: Path.join(tmp_dir, "static"),
        tmp_dir: tmp_dir
      ]

      clean_dir(tmp_dir)
      File.mkdir!(opts[:static_dir])

      entry_file_path = Path.join(tmp_dir, "MyPage.entry.js")
      File.write(entry_file_path, "export const myVar 123;\n")

      assert_raise RuntimeError,
                   "esbuild bundler failed for entry file: #{entry_file_path} (probably there were JavaScript syntax errors)",
                   fn ->
                     bundle(MyPage, entry_file_path, "my_bundle_name", opts)
                   end

      assert File.ls!(opts[:static_dir]) == []
    end

    test "raises when the generated bundle exceeds the specified :max_bundle_size (and does not copy the bundle to the static dir in such case) " do
      node_modules_path = Path.join([@root_dir, "assets", "node_modules"])

      tmp_dir =
        Path.join([Reflection.tmp_dir(), "tests", "compiler", "bundle_4_exceeds_max_size"])

      opts = [
        esbuild_bin_path: Path.join([node_modules_path, ".bin", "esbuild"]),
        node_modules_path: node_modules_path,
        static_dir: Path.join(tmp_dir, "static"),
        tmp_dir: tmp_dir
      ]

      clean_dir(tmp_dir)
      File.mkdir!(opts[:static_dir])

      entry_file_path = Path.join(tmp_dir, "MyPage.entry.js")
      File.write!(entry_file_path, "export const myVar = 123;\n")

      Application.put_env(:hologram, :max_bundle_size, 10)

      on_exit(fn ->
        Application.delete_env(:hologram, :max_bundle_size)
      end)

      exception =
        assert_raise RuntimeError, fn ->
          bundle(MyPage, entry_file_path, "my_bundle_name", opts)
        end

      assert exception.message =~ "early warning system"
      assert File.ls!(opts[:static_dir]) == []
    end
  end

  test "create_page_entry_files/7", %{
    call_graph: call_graph,
    ir_plt: ir_plt,
    runtime_mfas: runtime_mfas
  } do
    opts = [
      js_dir: @js_dir,
      tmp_dir: Path.join([@tmp_dir, "tests", "compiler", "create_page_entry_files_7"])
    ]

    clean_dir(opts[:tmp_dir])

    page_modules = Reflection.list_pages()

    call_graph_without_runtime_mfas =
      call_graph
      |> CallGraph.clone()
      |> CallGraph.remove_runtime_mfas!(runtime_mfas)

    result =
      create_page_entry_files(
        page_modules,
        call_graph_without_runtime_mfas,
        ir_plt,
        PLT.start(),
        MapSet.new(),
        MapSet.new(),
        opts
      )

    assert Enum.count(result) == Enum.count(page_modules)

    Enum.each(result, fn {page_module, entry_file_path} ->
      assert page_module in page_modules

      module_name = Reflection.module_name(page_module)
      assert entry_file_path == Path.join(opts[:tmp_dir], "#{module_name}.entry.js")

      assert entry_file_path
             |> File.read!()
             |> String.contains?("Interpreter.defineElixirFunction")
    end)
  end

  test "create_page_entry_files/7 asks the call graph for its graph once and releases it", %{
    call_graph: call_graph,
    ir_plt: ir_plt,
    runtime_mfas: runtime_mfas
  } do
    opts = [
      js_dir: @js_dir,
      tmp_dir: Path.join([@tmp_dir, "tests", "compiler", "create_page_entry_files_7_shared"])
    ]

    clean_dir(opts[:tmp_dir])

    page_modules = Reflection.list_pages()

    %CallGraph{pid: pid} =
      call_graph_without_runtime_mfas =
      call_graph
      |> CallGraph.clone()
      |> CallGraph.remove_runtime_mfas!(runtime_mfas)

    count_shared_graphs = fn ->
      Enum.count(:persistent_term.get(), &match?({{CallGraph, _ref}, _graph}, &1))
    end

    shared_graphs_before = count_shared_graphs.()

    # Only the call graph's own process is traced, for the messages it receives.
    :erlang.trace(pid, true, [:receive])

    try do
      create_page_entry_files(
        page_modules,
        call_graph_without_runtime_mfas,
        ir_plt,
        PLT.start(),
        MapSet.new(),
        MapSet.new(),
        opts
      )
    after
      :erlang.trace(pid, false, [:receive])
    end

    ref = :erlang.trace_delivered(pid)
    assert_receive {:trace_delivered, ^pid, ^ref}

    {:messages, messages} = Process.info(self(), :messages)

    graph_requests =
      Enum.count(
        messages,
        &match?({:trace, ^pid, :receive, {:"$gen_call", _from, {:get, _fun}}}, &1)
      )

    assert length(page_modules) > 1
    assert graph_requests == 1
    assert count_shared_graphs.() == shared_graphs_before
  end

  test "create_page_entry_files/7 reads each module's IR once for all pages", %{
    call_graph: call_graph,
    ir_plt: ir_plt,
    runtime_mfas: runtime_mfas
  } do
    opts = [
      js_dir: @js_dir,
      tmp_dir: Path.join([@tmp_dir, "tests", "compiler", "create_page_entry_files_7_reads"])
    ]

    clean_dir(opts[:tmp_dir])

    page_modules = Reflection.list_pages()

    call_graph_without_runtime_mfas =
      call_graph
      |> CallGraph.clone()
      |> CallGraph.remove_runtime_mfas!(runtime_mfas)

    graph = CallGraph.get_graph(call_graph_without_runtime_mfas)
    module_info_plt = CallGraph.module_info_plt(call_graph)

    server_callback_analysis_by_templatable =
      CallGraph.server_callback_analysis_by_templatable(
        graph,
        page_modules ++ Reflection.list_components(),
        module_info_plt
      )

    # The Elixir modules each page reaches, split into protocols, which are read and rendered per
    # page, and the rest, which are read once for all pages.
    modules_by_page =
      Enum.map(page_modules, fn page_module ->
        graph
        |> CallGraph.list_page_mfas(
          page_module,
          server_callback_analysis_by_templatable,
          module_info_plt
        )
        |> Enum.map(fn {module, _function, _arity} -> module end)
        |> Enum.uniq()
        |> Enum.filter(&Reflection.elixir_module?(&1, ir_plt))
      end)

    {protocol_modules, other_modules} =
      modules_by_page
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.split_with(&Reflection.protocol?/1)

    protocol_reads =
      modules_by_page
      |> List.flatten()
      |> Enum.count(&(&1 in protocol_modules))

    # Call counts are kept per function for every process, so the tasks are counted too.
    :erlang.trace_pattern({PLT, :get!, 2}, true, [:call_count])

    try do
      create_page_entry_files(
        page_modules,
        call_graph_without_runtime_mfas,
        ir_plt,
        PLT.start(),
        MapSet.new(),
        MapSet.new(),
        opts
      )

      assert other_modules != []

      assert :erlang.trace_info({PLT, :get!, 2}, :call_count) ==
               {:call_count, length(other_modules) + protocol_reads}
    after
      :erlang.trace_pattern({PLT, :get!, 2}, false, [:call_count])
    end
  end

  test "create_page_entry_files/7 renders the module metadata from the given map", %{
    call_graph: call_graph,
    ir_plt: ir_plt,
    runtime_mfas: runtime_mfas
  } do
    opts = [
      js_dir: @js_dir,
      tmp_dir: Path.join([@tmp_dir, "tests", "compiler", "create_page_entry_files_7_metadata"])
    ]

    clean_dir(opts[:tmp_dir])

    page_modules = Reflection.list_pages()

    call_graph_without_runtime_mfas =
      call_graph
      |> CallGraph.clone()
      |> CallGraph.remove_runtime_mfas!(runtime_mfas)

    build = fn opts ->
      page_modules
      |> create_page_entry_files(
        call_graph_without_runtime_mfas,
        ir_plt,
        PLT.start(),
        MapSet.new(),
        MapSet.new(),
        opts
      )
      |> Enum.map(fn {page_module, entry_file_path} ->
        {page_module, File.read!(entry_file_path)}
      end)
    end

    module_metadata =
      call_graph
      |> CallGraph.module_info_plt()
      |> build_module_metadata()

    without_map = build.(opts)

    # Call counts are kept per function for every process, so the page tasks are counted too.
    # The baseline is a build that renders no metadata at all: whatever else in the phase loads a
    # module is counted there too, and the map must add nothing to it.
    count_module_loads = fn build_fun ->
      :erlang.trace_pattern({Code, :ensure_loaded?, 1}, true, [:call_count])

      try do
        result = build_fun.()
        {:call_count, count} = :erlang.trace_info({Code, :ensure_loaded?, 1}, :call_count)
        {result, count}
      after
        :erlang.trace_pattern({Code, :ensure_loaded?, 1}, false, [:call_count])
      end
    end

    Application.put_env(:hologram, :client_stacktraces, false)

    {_without_metadata, baseline_loads} =
      try do
        count_module_loads.(fn -> build.(opts) end)
      after
        Application.delete_env(:hologram, :client_stacktraces)
      end

    {with_map, loads} =
      count_module_loads.(fn -> build.(Keyword.put(opts, :module_metadata, module_metadata)) end)

    assert with_map == without_map
    {_page_module, first_page_js} = hd(with_map)
    assert String.contains?(first_page_js, "ERTS.registerModuleMetadata(")
    assert loads == baseline_loads
  end

  test "create_page_entry_files/7 with the component modules given", %{
    call_graph: call_graph,
    ir_plt: ir_plt,
    runtime_mfas: runtime_mfas
  } do
    opts = [
      js_dir: @js_dir,
      tmp_dir: Path.join([@tmp_dir, "tests", "compiler", "create_page_entry_files_7_components"])
    ]

    clean_dir(opts[:tmp_dir])

    page_modules = Reflection.list_pages()

    call_graph_without_runtime_mfas =
      call_graph
      |> CallGraph.clone()
      |> CallGraph.remove_runtime_mfas!(runtime_mfas)

    build = fn opts ->
      page_modules
      |> create_page_entry_files(
        call_graph_without_runtime_mfas,
        ir_plt,
        PLT.start(),
        MapSet.new(),
        MapSet.new(),
        opts
      )
      |> Enum.map(fn {page_module, entry_file_path} ->
        {page_module, File.read!(entry_file_path)}
      end)
    end

    opts_with_components = Keyword.put(opts, :components, Reflection.list_components())

    listed = build.(opts)
    given = build.(opts_with_components)

    assert given == listed
  end

  test "create_runtime_entry_file/6", %{ir_plt: ir_plt, runtime_mfas: runtime_mfas} do
    opts = [
      js_dir: @js_dir,
      tmp_dir: Path.join([@tmp_dir, "tests", "compiler", "create_runtime_entry_file_6"])
    ]

    clean_dir(opts[:tmp_dir])

    entry_file_path =
      create_runtime_entry_file(runtime_mfas, ir_plt, PLT.start(), MapSet.new(), [], opts)

    assert entry_file_path == Path.join(opts[:tmp_dir], "runtime.entry.js")

    assert entry_file_path
           |> File.read!()
           |> String.contains?("Interpreter.defineElixirFunction")
  end

  test "diff_module_info_plts/2" do
    info = fn digest, mtime ->
      %{digest: digest, mtime: mtime, size: 1, page?: false, component?: false}
    end

    old_plt =
      PLT.start()
      |> PLT.put(:module_1, info.(1, 100))
      |> PLT.put(:module_3, info.(3, 100))
      |> PLT.put(:module_5, info.(5, 100))
      |> PLT.put(:module_6, info.(6, 100))
      |> PLT.put(:module_7, info.(7, 100))
      |> PLT.put(:module_8, info.(8, 100))

    new_plt =
      PLT.start()
      |> PLT.put(:module_1, info.(1, 100))
      |> PLT.put(:module_2, info.(2, 100))
      |> PLT.put(:module_3, info.(33, 100))
      |> PLT.put(:module_4, info.(4, 100))
      |> PLT.put(:module_6, info.(66, 100))
      |> PLT.put(:module_8, info.(8, 200))

    result = diff_module_info_plts(old_plt, new_plt)

    keys =
      result
      |> Map.keys()
      |> Enum.sort()

    assert keys == [:added_modules, :edited_modules, :removed_modules]
    assert Enum.sort(result.added_modules) == [:module_2, :module_4]
    assert Enum.sort(result.removed_modules) == [:module_5, :module_7]
    assert Enum.sort(result.edited_modules) == [:module_3, :module_6]
  end

  describe "encode_reachable_functions/5" do
    setup do
      # A PLT per test, so one test's cache can never stand in for another's encoding.
      [encode_plt: PLT.start()]
    end

    test "encodes every Elixir function of the given MFAs", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      module_info_plt: module_info_plt
    } do
      mfas = [{Enum, :into, 2}, {Module24, :template, 0}, {Module24, :action, 3}]

      encode_reachable_functions(mfas, ir_plt, encode_plt, MapSet.new(), module_info_plt)

      assert {:ok, into_js} = PLT.get(encode_plt, {Enum, :into, 2})

      assert String.starts_with?(
               into_js,
               ~s/Interpreter.defineElixirFunction("Enum", "into", 2, "public"/
             )

      assert {:ok, template_js} = PLT.get(encode_plt, {Module24, :template, 0})
      assert String.starts_with?(template_js, "Interpreter.defineElixirFunction(")

      assert {:ok, action_js} = PLT.get(encode_plt, {Module24, :action, 3})
      assert String.starts_with?(action_js, "Interpreter.defineElixirFunction(")

      assert PLT.size(encode_plt) == 3
    end

    test "skips Erlang MFAs", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      module_info_plt: module_info_plt
    } do
      encode_reachable_functions(
        [{:erlang, :hd, 1}],
        ir_plt,
        encode_plt,
        MapSet.new(),
        module_info_plt
      )

      assert PLT.size(encode_plt) == 0
    end

    test "skips protocol modules", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      module_info_plt: module_info_plt
    } do
      encode_reachable_functions(
        [{String.Chars, :to_string, 1}],
        ir_plt,
        encode_plt,
        MapSet.new(),
        module_info_plt
      )

      assert PLT.size(encode_plt) == 0
    end

    test "skips functions already in the PLT", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      module_info_plt: module_info_plt
    } do
      PLT.put(encode_plt, {Enum, :into, 2}, "cached")

      encode_reachable_functions(
        [{Enum, :into, 2}],
        ir_plt,
        encode_plt,
        MapSet.new(),
        module_info_plt
      )

      assert PLT.get(encode_plt, {Enum, :into, 2}) == {:ok, "cached"}
    end

    test "remembers a function the module does not define", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      module_info_plt: module_info_plt
    } do
      mfa = {Enum, :hologram_undefined_fun, 9}

      encode_reachable_functions([mfa], ir_plt, encode_plt, MapSet.new(), module_info_plt)

      assert PLT.get(encode_plt, mfa) == {:ok, nil}
    end

    test "reads each module's IR once, however many of its MFAs are given, repeats included", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      module_info_plt: module_info_plt
    } do
      mfas = [
        {Enum, :into, 2},
        {Enum, :map, 2},
        {Enum, :into, 2},
        {Module24, :template, 0},
        {Module24, :action, 3}
      ]

      # Call counts are kept per function for every process, so the tasks the function starts
      # are counted too.
      :erlang.trace_pattern({PLT, :get!, 2}, true, [:call_count])

      try do
        encode_reachable_functions(mfas, ir_plt, encode_plt, MapSet.new(), module_info_plt)

        assert :erlang.trace_info({PLT, :get!, 2}, :call_count) == {:call_count, 2}
      after
        :erlang.trace_pattern({PLT, :get!, 2}, false, [:call_count])
      end
    end

    test "skips a module the module info PLT marks as a protocol, without asking it", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      module_info_plt: module_info_plt
    } do
      {:ok, info} = PLT.get(module_info_plt, Enum)
      module_info_plt = PLT.clone(module_info_plt)
      PLT.put(module_info_plt, Enum, %{info | protocol?: true})

      encode_reachable_functions(
        [{Enum, :into, 2}],
        ir_plt,
        encode_plt,
        MapSet.new(),
        module_info_plt
      )

      assert PLT.size(encode_plt) == 0
    end

    test "returns :ok", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      module_info_plt: module_info_plt
    } do
      assert encode_reachable_functions([], ir_plt, encode_plt, MapSet.new(), module_info_plt) ==
               :ok
    end
  end

  describe "get_erlang_function_js/4" do
    test ":erlang module function that is implemented" do
      result = get_erlang_function_js(:erlang, :+, 2, @erlang_js_dir)

      expected =
        normalize_newlines("""
        (left, right) => {
            if (!Type.isNumber(left) || !Type.isNumber(right)) {
              Interpreter.raiseBifError("badarith", "erlang", "+", [left, right]);
            }

            const [type, leftValue, rightValue] = Type.maybeNormalizeNumberTerms(
              left,
              right,
            );

            const result = leftValue.value + rightValue.value;

            return type === "float" ? Type.float(result) : Type.integer(result);
          }\
        """)

      assert normalize_newlines(result) == expected
    end

    test ":erlang module function that is not implemented" do
      result = Compiler.get_erlang_function_js(:erlang, :not_implemented, 2, @erlang_js_dir)
      assert result == nil
    end

    test ":maps module function that is implemented" do
      result = Compiler.get_erlang_function_js(:maps, :get, 2, @erlang_js_dir)

      expected =
        normalize_newlines("""
        (key, map) => {
            if (!Type.isMap(map)) {
              Interpreter.raiseBifError(["badmap", map], "erlang", "map_get", [
                key,
                map,
              ]);
            }

            const encodedKey = Type.encodeMapKey(key);

            if (map.data[encodedKey]) {
              return map.data[encodedKey][1];
            }

            Interpreter.raiseBifError(["badkey", key], "erlang", "map_get", [key, map]);
          }\
        """)

      assert normalize_newlines(result) == expected
    end

    test ":maps module function that is not implemented" do
      result = Compiler.get_erlang_function_js(:maps, :not_implemented, 2, @erlang_js_dir)
      assert result == nil
    end

    test "no comment lines between start marker and key" do
      result =
        Compiler.get_erlang_function_js(:erlang_fixture, :no_comments, 1, @fixtures_compiler_dir)

      expected =
        normalize_newlines("""
        (x) => {
            return x;
          }\
        """)

      assert normalize_newlines(result) == expected
    end

    test "single comment line between start marker and key" do
      result =
        Compiler.get_erlang_function_js(
          :erlang_fixture,
          :single_comment,
          0,
          @fixtures_compiler_dir
        )

      expected =
        normalize_newlines("""
        () => {
            return 1;
          }\
        """)

      assert normalize_newlines(result) == expected
    end

    test "multiple comment lines between start marker and key" do
      result =
        Compiler.get_erlang_function_js(
          :erlang_fixture,
          :multiple_comments,
          2,
          @fixtures_compiler_dir
        )

      expected =
        normalize_newlines("""
        (a, b) => {
            return a + b;
          }\
        """)

      assert normalize_newlines(result) == expected
    end

    test "module file doesn't exist" do
      result = Compiler.get_erlang_function_js(:non_existing_module, :some_fun, 1, @erlang_js_dir)
      assert result == nil
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

  describe "install_js_deps/1" do
    setup do
      setup_js_deps_test("install_js_deps_1")
    end

    @tag timeout: 300_000
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

    @tag timeout: 300_000
    test "creates a file containing the digest of package.json", %{
      assets_dir: assets_dir,
      build_dir: build_dir
    } do
      install_js_deps(assets_dir, build_dir)

      package_json_digest_path = Path.join(build_dir, "package_json_digest.bin")
      assert File.exists?(package_json_digest_path)
    end

    test "raises RuntimeError if npm install command fails", %{
      assets_dir: assets_dir,
      build_dir: build_dir
    } do
      fixture_package_json_path = Path.join(assets_dir, "package.json")
      File.rm!(fixture_package_json_path)

      assert_raise RuntimeError, "npm install command failed", fn ->
        install_js_deps(assets_dir, build_dir)
      end

      node_modules_dir = Path.join(assets_dir, "node_modules")
      refute File.exists?(node_modules_dir)

      package_lock_json_path = Path.join(assets_dir, "package-lock.json")
      assert File.exists?(package_lock_json_path)

      package_json_digest_path = Path.join(build_dir, "package_json_digest.bin")
      refute File.exists?(package_json_digest_path)
    end
  end

  describe "list_component_usages/1" do
    test "collects plain and nested usages, in template order" do
      usages =
        Module28
        |> IR.for_module()
        |> list_component_usages()

      assert usages == [
               {Module27, [{"a", {:ok, "1"}}, {"b", :unknown}], false},
               {Module27, [{"a", {:ok, "2"}}], false},
               {Module27, [{"b", {:ok, "3"}}], false}
             ]
    end

    test "reports the value of a prop written as a literal expression" do
      usages =
        Module38
        |> IR.for_module()
        |> list_component_usages()

      assert usages == [
               {Module37, [{"size", {:ok, :small}}, {"label", {:ok, "abc"}}, {"free", :unknown}],
                false}
             ]
    end

    test "flags a usage carrying a spread" do
      usages =
        Module29
        |> IR.for_module()
        |> list_component_usages()

      assert usages == [
               {Module27, [{"a", {:ok, "1"}}], true}
             ]
    end

    test "skips dynamic tags" do
      usages =
        Module30
        |> IR.for_module()
        |> list_component_usages()

      assert usages == []
    end

    test "returns an empty list for a module without component usages" do
      usages =
        Module27
        |> IR.for_module()
        |> list_component_usages()

      assert usages == []
    end
  end

  test "list_components/1" do
    info = fn page?, component? ->
      %{digest: 1, mtime: 1, size: 1, page?: page?, component?: component?}
    end

    plt =
      PLT.start()
      |> PLT.put(Module3, info.(false, true))
      |> PLT.put(Module1, info.(false, false))
      |> PLT.put(Module2, info.(true, false))
      |> PLT.put(Module11, info.(false, true))

    assert list_components(plt) == [Module11, Module3]
  end

  describe "list_js_import_modules/3" do
    test "returns the modules that declare JS imports", %{
      ir_plt: ir_plt,
      module_info_plt: module_info_plt
    } do
      mfas = [{Module12, :func, 0}, {Enum, :map, 2}, {Module14, :func, 0}]

      assert list_js_import_modules(mfas, ir_plt, module_info_plt) == [Module12, Module14]
    end

    test "filters out Erlang modules, modules without JS imports and duplicates", %{
      ir_plt: ir_plt,
      module_info_plt: module_info_plt
    } do
      mfas = [
        {:erlang, :+, 2},
        {Enum, :map, 2},
        {Module13, :func, 0},
        {Module12, :func, 0},
        {Module12, :func_2, 0}
      ]

      assert list_js_import_modules(mfas, ir_plt, module_info_plt) == [Module12]
    end

    test "a module the module info PLT marks as having no imports is not asked", %{
      ir_plt: ir_plt,
      module_info_plt: module_info_plt
    } do
      {:ok, info} = PLT.get(module_info_plt, Module12)
      module_info_plt = PLT.clone(module_info_plt)
      PLT.put(module_info_plt, Module12, %{info | js_imports?: false})

      assert list_js_import_modules([{Module12, :func, 0}], ir_plt, module_info_plt) == []
    end

    test "a nil module info PLT asks every module", %{ir_plt: ir_plt} do
      assert list_js_import_modules([{Module12, :func, 0}], ir_plt, nil) == [Module12]
    end
  end

  test "list_pages/1" do
    info = fn page?, component? ->
      %{digest: 1, mtime: 1, size: 1, page?: page?, component?: component?}
    end

    plt =
      PLT.start()
      |> PLT.put(Module3, info.(false, true))
      |> PLT.put(Module1, info.(false, false))
      |> PLT.put(Module2, info.(true, false))
      |> PLT.put(Module11, info.(true, false))

    assert list_pages(plt) == [Module11, Module2]
  end

  describe "maybe_install_js_deps/1" do
    setup do
      setup_js_deps_test("maybe_install_js_deps_1")
    end

    @tag timeout: 300_000
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

    @tag timeout: 300_000
    test "package-lock.json file doesn't exist", %{assets_dir: assets_dir, build_dir: build_dir} do
      install_js_deps(assets_dir, build_dir)

      package_lock_json_path = Path.join(assets_dir, "package-lock.json")
      File.rm!(package_lock_json_path)

      assert maybe_install_js_deps(assets_dir, build_dir) == :ok
      assert File.exists?(package_lock_json_path)
    end

    @tag timeout: 300_000
    test "package.json file changed", %{assets_dir: assets_dir, build_dir: build_dir} do
      install_js_deps(assets_dir, build_dir)

      package_json_digest_path = Path.join(build_dir, "package_json_digest.bin")
      package_json_digest = File.read!(package_json_digest_path)

      package_json_path = Path.join(assets_dir, "package.json")
      File.write!(package_json_path, "{}")

      assert maybe_install_js_deps(assets_dir, build_dir) == :ok
      assert File.read!(package_json_digest_path) != package_json_digest
    end

    @tag timeout: 300_000
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
      test_tmp_dir = Path.join([@tmp_dir, "tests", "compiler", "maybe_load_call_graph_1"])

      build_dir = Path.join(test_tmp_dir, "build")
      clean_dir(build_dir)

      dump_path = Path.join(build_dir, Reflection.call_graph_dump_file_name())

      [build_dir: build_dir, dump_path: dump_path]
    end

    test "dump file doesn't exist", %{build_dir: build_dir, dump_path: dump_path} do
      assert {call_graph = %CallGraph{}, ^dump_path} = maybe_load_call_graph(build_dir)
      assert CallGraph.get_graph(call_graph) == Digraph.new()
    end

    test "dump file exists", %{build_dir: build_dir, call_graph: call_graph, dump_path: dump_path} do
      CallGraph.dump(call_graph, dump_path)

      assert {loaded_call_graph = %CallGraph{}, ^dump_path} = maybe_load_call_graph(build_dir)
      assert CallGraph.get_graph(loaded_call_graph) == CallGraph.get_graph(call_graph)
    end
  end

  describe "maybe_load_ir_plt/1" do
    setup do
      test_tmp_dir = Path.join([@tmp_dir, "tests", "compiler", "maybe_load_ir_plt_1"])

      build_dir = Path.join(test_tmp_dir, "build")
      clean_dir(build_dir)

      dump_path = Path.join(build_dir, Reflection.ir_plt_dump_file_name())

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

  describe "maybe_load_module_info_plt/1" do
    setup do
      test_tmp_dir = Path.join([@tmp_dir, "tests", "compiler", "maybe_load_module_info_plt_1"])

      build_dir = Path.join(test_tmp_dir, "build")
      clean_dir(build_dir)

      dump_path = Path.join(build_dir, Reflection.module_info_plt_dump_file_name())

      [build_dir: build_dir, dump_path: dump_path]
    end

    test "dump file doesn't exist", %{build_dir: build_dir, dump_path: dump_path} do
      assert {plt = %PLT{}, ^dump_path, nil} = maybe_load_module_info_plt(build_dir)
      assert PLT.get_all(plt) == %{}
    end

    test "dump file exists", %{build_dir: build_dir, dump_path: dump_path} do
      PLT.start()
      |> PLT.put(:a, 1)
      |> PLT.put(:b, 2)
      |> PLT.dump(dump_path)

      dumped_at = File.stat!(dump_path, time: :posix).mtime

      assert {plt = %PLT{}, ^dump_path, ^dumped_at} = maybe_load_module_info_plt(build_dir)
      assert PLT.get_all(plt) == %{a: 1, b: 2}
    end
  end

  describe "patch_ir_plt!/3" do
    setup do
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
        edited_modules: [Module3, Module4]
      }

      patch_ir_plt!(ir_plt, module_digests_diff)

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

    test "updates entries of edited modules", %{ir_plt: ir_plt} do
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

    # Reproduces the state Phoenix's code reloader leaves behind in an umbrella:
    # it compiles with --purge-consolidation-path-if-stale, which removes the
    # umbrella root consolidated dir while the protocol modules stay loaded from
    # it. Resolving such a module through :code.which/1 alone raises, which is
    # what the single-app path would do here - see the removal note on
    # Hologram.Compiler.resolve_beam_source/2.
    # TODO: Remove when resolve_beam_source/2 goes (see the removal note there).
    test "umbrella project, module loaded from a purged consolidated beam" do
      module = Module26
      {^module, bytecode, _beam_path} = :code.get_object_code(module)

      # The module's own beam stays on the code path - only the consolidated copy
      # it gets reloaded from below is gone.
      {:module, ^module} =
        :code.load_binary(module, ~c"/removed/consolidated/#{module}.beam", bytecode)

      on_exit(fn ->
        :code.purge(module)
        {:module, ^module} = :code.load_file(module)
      end)

      ir_plt = PLT.start()
      umbrella_dir = Path.join(@fixtures_dir, "umbrella")

      module_digests_diff = %{
        added_modules: [module],
        removed_modules: [],
        edited_modules: []
      }

      Mix.Project.in_project(:umbrella_fixture, umbrella_dir, [app: nil], fn _module ->
        patch_ir_plt!(ir_plt, module_digests_diff)
      end)

      assert {:ok, %IR.ModuleDefinition{module: %IR.AtomType{value: ^module}}} =
               PLT.get(ir_plt, module)
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
                     },
                     line: 11,
                     blame: %{params: [":a", ":b"], guards: []}
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
                     },
                     # The AST reconstructed from BEAM debug info carries the
                     # first clause's line on every clause of a function.
                     line: 11,
                     blame: %{params: [":b", ":c"], guards: []}
                   }
                 },
                 %IR.FunctionDefinition{
                   name: :fun_3,
                   arity: 1,
                   visibility: :public,
                   clause: %IR.FunctionClause{
                     params: [%IR.Variable{name: :x, version: 0}],
                     guards: [],
                     body: %IR.Block{
                       expressions: [%IR.Variable{name: :x, version: 0}]
                     },
                     line: 19,
                     blame: %{params: ["x"], guards: []}
                   }
                 }
               ]
             }
           }
  end

  test "prune_module_def/2 prunes protocol dispatcher clauses to included implementations" do
    reachable_mfas = [
      {String.Chars, :impl_for, 1},
      {String.Chars, :impl_for!, 1},
      {String.Chars, :struct_impl_for, 1},
      {String.Chars, :to_string, 1},
      {String.Chars.Atom, :__impl__, 1},
      {String.Chars.Atom, :to_string, 1},
      {String.Chars.URI, :__impl__, 1},
      {String.Chars.URI, :to_string, 1}
    ]

    js =
      String.Chars
      |> IR.for_module()
      |> prune_module_def(reachable_mfas)
      |> Encoder.encode_ir(%Context{module: String.Chars, async_mfas: MapSet.new()})

    assert String.contains?(
             js,
             ~s/Interpreter.defineElixirFunction("String.Chars", "impl_for!", 1, "public"/
           )

    assert String.contains?(js, ~s/Type.atom("Elixir.String.Chars.Atom")/)
    assert String.contains?(js, ~s/Type.atom("Elixir.String.Chars.URI")/)

    refute String.contains?(js, "Elixir.String.Chars.Version")
    refute String.contains?(js, "Hologram.Test.Fixtures.Compiler.CallGraph.Module12")
  end

  describe "validate_prop_usages/2" do
    test "doesn't raise when every required prop is written at the usage" do
      plt = PLT.put(PLT.start(), Module32, IR.for_module(Module32))

      assert validate_prop_usages([Module32], plt) == :ok
    end

    test "raises when a required prop is missing from the usage" do
      # The offending usage is built as IR rather than as a file fixture, because a file fixture
      # would raise in the compile.hologram Mix task tests, which compile the whole project.
      ir =
        IR.for_code(
          ~s/[{:component, Hologram.Test.Fixtures.Compiler.Module31, [{"label", [text: "abc"]}], []}]/,
          %Context{}
        )

      plt = PLT.put(PLT.start(), Module32, module_ir_with_template(ir))

      expected_msg =
        "component Hologram.Test.Fixtures.Compiler.Module31 is missing required prop " <>
          ~s/"size" in Hologram.Test.Fixtures.Compiler.Module32's template/

      assert_raise Hologram.CompileError, expected_msg, fn ->
        validate_prop_usages([Module32], plt)
      end
    end

    test "doesn't raise when the usage carries a spread" do
      plt = PLT.put(PLT.start(), Module34, IR.for_module(Module34))

      assert validate_prop_usages([Module34], plt) == :ok
    end

    test "doesn't raise when the required prop is sourced from context" do
      plt = PLT.put(PLT.start(), Module36, IR.for_module(Module36))

      assert validate_prop_usages([Module36], plt) == :ok
    end

    # A component node is an ordinary 4-tuple, so code outside the template can hold one without any
    # template rendering it.
    test "ignores a component tuple returned by a non-template function" do
      plt = PLT.put(PLT.start(), Module40, IR.for_module(Module40))

      assert validate_prop_usages([Module40], plt) == :ok
    end

    test "skips modules that are not in the IR PLT" do
      assert validate_prop_usages([Module32], PLT.start()) == :ok
    end

    test "doesn't raise when a written value is in the prop's :values list" do
      plt = PLT.put(PLT.start(), Module38, IR.for_module(Module38))

      assert validate_prop_usages([Module38], plt) == :ok
    end

    test "raises when a literal expression value is not in the prop's :values list" do
      ir =
        IR.for_code(
          ~s/[{:component, Hologram.Test.Fixtures.Compiler.Module37, [{"size", [expression: {:huge}]}], []}]/,
          %Context{}
        )

      plt = PLT.put(PLT.start(), Module38, module_ir_with_template(ir))

      expected_msg =
        ~s/prop "size" of component Hologram.Test.Fixtures.Compiler.Module37 must be one of / <>
          "[:small, :large], got: :huge, " <>
          "in Hologram.Test.Fixtures.Compiler.Module38's template"

      assert_raise Hologram.CompileError, expected_msg, fn ->
        validate_prop_usages([Module38], plt)
      end
    end

    test "raises when a text value is not in the prop's :values list" do
      ir =
        IR.for_code(
          ~s/[{:component, Hologram.Test.Fixtures.Compiler.Module37, [{"label", [text: "nope"]}], []}]/,
          %Context{}
        )

      plt = PLT.put(PLT.start(), Module38, module_ir_with_template(ir))

      expected_msg =
        ~s/prop "label" of component Hologram.Test.Fixtures.Compiler.Module37 must be one of / <>
          ~s/["abc", "xyz"], got: "nope", / <>
          "in Hologram.Test.Fixtures.Compiler.Module38's template"

      assert_raise Hologram.CompileError, expected_msg, fn ->
        validate_prop_usages([Module38], plt)
      end
    end

    test "raises for a value written at a usage that also carries a spread" do
      ir =
        IR.for_code(
          ~s/[{:component, Hologram.Test.Fixtures.Compiler.Module37, [{"size", [expression: {:huge}]}, {:spread, {vars.props}}], []}]/,
          %Context{}
        )

      plt = PLT.put(PLT.start(), Module38, module_ir_with_template(ir))

      expected_msg =
        ~s/prop "size" of component Hologram.Test.Fixtures.Compiler.Module37 must be one of / <>
          "[:small, :large], got: :huge, " <>
          "in Hologram.Test.Fixtures.Compiler.Module38's template"

      assert_raise Hologram.CompileError, expected_msg, fn ->
        validate_prop_usages([Module38], plt)
      end
    end

    test "raises when a composite literal value is not in the prop's :values list" do
      ir =
        IR.for_code(
          ~s/[{:component, Hologram.Test.Fixtures.Compiler.Module39, [{"size", [expression: {[:huge]}]}], []}]/,
          %Context{}
        )

      plt = PLT.put(PLT.start(), Module38, module_ir_with_template(ir))

      expected_msg =
        ~s/prop "size" of component Hologram.Test.Fixtures.Compiler.Module39 must be one of / <>
          "[[:small], [:large]], got: [:huge], " <>
          "in Hologram.Test.Fixtures.Compiler.Module38's template"

      assert_raise Hologram.CompileError, expected_msg, fn ->
        validate_prop_usages([Module38], plt)
      end
    end

    test "doesn't raise when a composite literal value is in the prop's :values list" do
      ir =
        IR.for_code(
          ~s/[{:component, Hologram.Test.Fixtures.Compiler.Module39, [{"size", [expression: {[:small]}]}], []}]/,
          %Context{}
        )

      plt = PLT.put(PLT.start(), Module38, module_ir_with_template(ir))

      assert validate_prop_usages([Module38], plt) == :ok
    end

    # One expression anywhere inside makes the whole composite unknowable until it runs.
    test "doesn't raise when a composite value holds an expression" do
      ir =
        IR.for_code(
          ~s/[{:component, Hologram.Test.Fixtures.Compiler.Module39, [{"size", [expression: {[vars.x]}]}], []}]/,
          %Context{}
        )

      plt = PLT.put(PLT.start(), Module38, module_ir_with_template(ir))

      assert validate_prop_usages([Module38], plt) == :ok
    end

    test "doesn't raise when the value is not known at compile time" do
      ir =
        IR.for_code(
          ~s/[{:component, Hologram.Test.Fixtures.Compiler.Module37, [{"size", [expression: {vars.x}]}], []}]/,
          %Context{}
        )

      plt = PLT.put(PLT.start(), Module38, module_ir_with_template(ir))

      assert validate_prop_usages([Module38], plt) == :ok
    end
  end

  describe "validate_page_modules/2" do
    # The module info PLT entries of the given pages: the fixture PLT's for file fixtures, and the
    # given ones for pages defined in a test, which are compiled without debug info.
    defp page_module_info_plt(module_info_plt, file_pages, inline_entries) do
      file_entries = Enum.map(file_pages, &{&1, PLT.get!(module_info_plt, &1)})

      PLT.start(items: file_entries ++ inline_entries)
    end

    test "doesn't raise any error if all pages have a route and a layout specified", %{
      module_info_plt: module_info_plt
    } do
      plt = page_module_info_plt(module_info_plt, [Module9, Module11], [])

      assert validate_page_modules([Module9, Module11], plt) == :ok
    end

    test "raises error if any of the pages doesn't have a route specified", %{
      module_info_plt: module_info_plt
    } do
      # Inline fixture used, because file fixture would raise error in compile.hologram Mix task tests.
      defmodule InlinePageModuleFixture1 do
        use Hologram.Page

        layout Hologram.Test.Fixtures.LayoutFixture

        @impl Page
        def template do
          ~HOLO""
        end
      end

      plt =
        page_module_info_plt(module_info_plt, [Module11], [
          {InlinePageModuleFixture1,
           %{route: nil, layout_module: Hologram.Test.Fixtures.LayoutFixture}}
        ])

      expected_msg =
        "page 'Hologram.CompilerTest.InlinePageModuleFixture1' doesn't have a route specified (use the route/1 macro to fix it)"

      assert_raise Hologram.CompileError, expected_msg, fn ->
        validate_page_modules([Module11, InlinePageModuleFixture1], plt)
      end
    end

    test "raises error if any of the pages doesn't have a layout specified", %{
      module_info_plt: module_info_plt
    } do
      # Inline fixture used, because file fixture would raise error in compile.hologram Mix task tests.
      defmodule InlinePageModuleFixture2 do
        use Hologram.Page

        route "/hologram-compilertest-inline-page-module-fixture-2"

        @impl Page
        def template do
          ~HOLO""
        end
      end

      plt =
        page_module_info_plt(module_info_plt, [Module11], [
          {InlinePageModuleFixture2,
           %{route: "/hologram-compilertest-inline-page-module-fixture-2", layout_module: nil}}
        ])

      expected_msg =
        "page 'Hologram.CompilerTest.InlinePageModuleFixture2' doesn't have a layout module specified (use the layout/1 macro to fix it)"

      assert_raise Hologram.CompileError, expected_msg, fn ->
        validate_page_modules([Module11, InlinePageModuleFixture2], plt)
      end
    end

    test "raises error if any of the pages has a route that is not a string", %{
      module_info_plt: module_info_plt
    } do
      plt =
        page_module_info_plt(module_info_plt, [Module11], [
          {Module9, %{route: :admin, layout_module: Hologram.Test.Fixtures.LayoutFixture}}
        ])

      expected_msg =
        "page 'Hologram.Test.Fixtures.Compiler.Module9' has a route that is not a string: :admin (pass a string to the route/1 macro to fix it)"

      assert_raise Hologram.CompileError, expected_msg, fn ->
        validate_page_modules([Module11, Module9], plt)
      end
    end

    test "asks the page for a route built at runtime, and accepts a string", %{
      module_info_plt: module_info_plt
    } do
      # Inline fixture used, because file fixture would raise error in compile.hologram Mix task tests.
      defmodule InlinePageModuleFixture3 do
        use Hologram.Page

        @prefix "hologram-compilertest"

        route "/#{@prefix}/inline-page-module-fixture-3"

        layout Hologram.Test.Fixtures.LayoutFixture

        @impl Page
        def template do
          ~HOLO""
        end
      end

      plt =
        page_module_info_plt(module_info_plt, [], [
          {InlinePageModuleFixture3,
           %{route: nil, layout_module: Hologram.Test.Fixtures.LayoutFixture}}
        ])

      assert validate_page_modules([InlinePageModuleFixture3], plt) == :ok
    end

    test "raises error if a route built at runtime is not a string", %{
      module_info_plt: module_info_plt
    } do
      # Inline fixture used, because file fixture would raise error in compile.hologram Mix task tests.
      defmodule InlinePageModuleFixture4 do
        use Hologram.Page

        route String.to_existing_atom("admin")

        layout Hologram.Test.Fixtures.LayoutFixture

        @impl Page
        def template do
          ~HOLO""
        end
      end

      plt =
        page_module_info_plt(module_info_plt, [], [
          {InlinePageModuleFixture4,
           %{route: nil, layout_module: Hologram.Test.Fixtures.LayoutFixture}}
        ])

      expected_msg =
        "page 'Hologram.CompilerTest.InlinePageModuleFixture4' has a route that is not a string: :admin (pass a string to the route/1 macro to fix it)"

      assert_raise Hologram.CompileError, expected_msg, fn ->
        validate_page_modules([InlinePageModuleFixture4], plt)
      end
    end
  end
end
