defmodule Hologram.CompilerTest do
  use Hologram.Test.BasicCase, async: false
  use Hologram.Query

  import Hologram.Compiler

  alias Hologram.Auth
  alias Hologram.Commons.PLT
  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Digraph
  alias Hologram.Compiler.Encoder
  alias Hologram.Compiler.IR
  alias Hologram.Entity.Model
  alias Hologram.Query
  alias Hologram.Query.Registry
  alias Hologram.Query.Window
  alias Hologram.Reflection
  alias Hologram.Sync.Frame

  alias Hologram.Test.Fixtures.Component.Module11, as: ComponentModule11
  alias Hologram.Test.Fixtures.Component.Module16, as: ComponentModule16
  alias Hologram.Test.Fixtures.Component.Module24, as: ComponentModule24
  alias Hologram.Test.Fixtures.Entity.Module1, as: Entity1
  alias Hologram.Test.Fixtures.Entity.Module12, as: Entity12
  alias Hologram.Test.Fixtures.Entity.Module15, as: Entity15
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2
  alias Hologram.Test.Fixtures.Entity.Module3, as: Entity3
  alias Hologram.Test.Fixtures.Entity.Module4, as: Entity4
  alias Hologram.Test.Fixtures.Page.Module10, as: PageModule10
  alias Hologram.Test.Fixtures.Page.Module11, as: PageModule11
  alias Hologram.Test.Fixtures.Page.Module7, as: PageModule7
  alias Hologram.Test.Fixtures.Page.Module8, as: PageModule8

  alias Hologram.Test.Fixtures.Compiler.Module1
  alias Hologram.Test.Fixtures.Compiler.Module11
  alias Hologram.Test.Fixtures.Compiler.Module12
  alias Hologram.Test.Fixtures.Compiler.Module13
  alias Hologram.Test.Fixtures.Compiler.Module14
  alias Hologram.Test.Fixtures.Compiler.Module15
  alias Hologram.Test.Fixtures.Compiler.Module17
  alias Hologram.Test.Fixtures.Compiler.Module19
  alias Hologram.Test.Fixtures.Compiler.Module2
  alias Hologram.Test.Fixtures.Compiler.Module21
  alias Hologram.Test.Fixtures.Compiler.Module23
  alias Hologram.Test.Fixtures.Compiler.Module24
  alias Hologram.Test.Fixtures.Compiler.Module25
  alias Hologram.Test.Fixtures.Compiler.Module26
  alias Hologram.Test.Fixtures.Compiler.Module3
  alias Hologram.Test.Fixtures.Compiler.Module4
  alias Hologram.Test.Fixtures.Compiler.Module8
  alias Hologram.Test.Fixtures.Compiler.Module9

  @root_dir Reflection.root_dir()
  @assets_dir Path.join(@root_dir, "assets")
  @js_dir Path.join(@assets_dir, "js")
  @erlang_js_dir Path.join(@js_dir, "erlang")

  @fixtures_compiler_dir Path.join(@fixtures_dir, "compiler")
  @empty_sync_constants %{
    entity_types: MapSet.new(),
    prop_params: %{},
    sort_key_attributes: MapSet.new()
  }
  @tmp_dir Reflection.tmp_dir()

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
      runtime_mfas: CallGraph.list_runtime_mfas(call_graph, Reflection.list_pages())
    ]
  end

  describe "aggregate_js_imports/1" do
    test "empty MFAs list" do
      assert aggregate_js_imports([]) == %{imports: [], bindings: %{}}
    end

    test "filters out Erlang modules" do
      mfas = [{:erlang, :+, 2}, {:maps, :get, 2}]

      assert aggregate_js_imports(mfas) == %{imports: [], bindings: %{}}
    end

    test "no modules have JS imports" do
      mfas = [{Enum, :map, 2}, {Kernel, :+, 2}]

      assert aggregate_js_imports(mfas) == %{imports: [], bindings: %{}}
    end

    test "skips modules that use Hologram.JS but have no imports" do
      mfas = [{Module13, :func, 0}]

      assert aggregate_js_imports(mfas) == %{imports: [], bindings: %{}}
    end

    test "single module with imports" do
      mfas = [{Module12, :func, 0}, {Enum, :map, 2}]

      assert aggregate_js_imports(mfas) == %{
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

    test "multiple modules with imports from different sources" do
      mfas = [{Module12, :func, 0}, {Module17, :func, 0}]

      assert aggregate_js_imports(mfas) == %{
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

    test "deduplicates modules when multiple MFAs reference the same module" do
      mfas = [{Module12, :func_a, 0}, {Module12, :func_b, 1}]

      assert aggregate_js_imports(mfas) == %{
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

    test "deduplicates imports when multiple modules import the same export" do
      mfas = [{Module14, :func, 0}, {Module15, :func, 0}]

      assert aggregate_js_imports(mfas) == %{
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
  end

  describe "build_page_js/6" do
    setup %{call_graph: call_graph, runtime_mfas: runtime_mfas} do
      call_graph_without_runtime_mfas =
        call_graph
        |> CallGraph.clone()
        |> CallGraph.remove_runtime_mfas!(runtime_mfas)

      graph = CallGraph.get_graph(call_graph_without_runtime_mfas)
      templatables = Reflection.list_pages() ++ Reflection.list_components()

      server_callback_analysis_by_templatable =
        CallGraph.server_callback_analysis_by_templatable(graph, templatables)

      [
        call_graph: call_graph_without_runtime_mfas,
        server_callback_analysis_by_templatable: server_callback_analysis_by_templatable
      ]
    end

    test "has both Erlang and Elixir function defs", %{
      call_graph: call_graph,
      ir_plt: ir_plt,
      server_callback_analysis_by_templatable: server_callback_analysis_by_templatable
    } do
      result =
        build_page_js(
          Module24,
          call_graph,
          ir_plt,
          MapSet.new(),
          server_callback_analysis_by_templatable,
          @js_dir
        )

      js_fragment_1 = ~s/globalThis.Hologram.pageReachableFunctionDefs/
      js_fragment_2 = ~s/Interpreter.defineElixirFunction/
      js_fragment_3 = ~s/Interpreter.defineErlangFunction/

      assert String.contains?(result, js_fragment_1)
      assert String.contains?(result, js_fragment_2)
      assert String.contains?(result, js_fragment_3)
    end

    test "has only Elixir defs", %{
      call_graph: call_graph,
      ir_plt: ir_plt,
      server_callback_analysis_by_templatable: server_callback_analysis_by_templatable
    } do
      result =
        build_page_js(
          Module25,
          call_graph,
          ir_plt,
          MapSet.new(),
          server_callback_analysis_by_templatable,
          @js_dir
        )

      js_fragment_1 = ~s/globalThis.Hologram.pageReachableFunctionDefs/
      js_fragment_2 = ~s/Interpreter.defineElixirFunction/
      js_fragment_3 = ~s/Interpreter.defineErlangFunction/

      assert String.contains?(result, js_fragment_1)
      assert String.contains?(result, js_fragment_2)
      refute String.contains?(result, js_fragment_3)
    end

    test "no JS imports", %{
      call_graph: call_graph,
      ir_plt: ir_plt,
      server_callback_analysis_by_templatable: server_callback_analysis_by_templatable
    } do
      result =
        build_page_js(
          Module11,
          call_graph,
          ir_plt,
          MapSet.new(),
          server_callback_analysis_by_templatable,
          @js_dir
        )

      refute String.contains?(result, "import {")
      refute String.contains?(result, "registerJsBindings")
    end

    test "single JS import", %{
      call_graph: call_graph,
      ir_plt: ir_plt,
      server_callback_analysis_by_templatable: server_callback_analysis_by_templatable
    } do
      result =
        build_page_js(
          Module19,
          call_graph,
          ir_plt,
          MapSet.new(),
          server_callback_analysis_by_templatable,
          @js_dir
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
      call_graph: call_graph,
      ir_plt: ir_plt,
      server_callback_analysis_by_templatable: server_callback_analysis_by_templatable
    } do
      result =
        build_page_js(
          Module21,
          call_graph,
          ir_plt,
          MapSet.new(),
          server_callback_analysis_by_templatable,
          @js_dir
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
      call_graph: call_graph,
      ir_plt: ir_plt,
      server_callback_analysis_by_templatable: server_callback_analysis_by_templatable
    } do
      result =
        build_page_js(
          Module23,
          call_graph,
          ir_plt,
          MapSet.new(),
          server_callback_analysis_by_templatable,
          @js_dir
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
  end

  test "build_call_graph/0" do
    assert %CallGraph{} = call_graph = build_call_graph()

    assert CallGraph.has_vertex?(call_graph, {Compiler, :build_call_graph, 1})
  end

  describe "build_page_windows/3" do
    setup %{call_graph: call_graph} do
      [page_windows: build_page_windows(Reflection.list_pages(), call_graph)]
    end

    test "gives a page the window of a component it renders", %{page_windows: page_windows} do
      window_id =
        Entity2
        |> filter(a: true)
        |> Query.normalize()
        |> Window.derive()
        |> Registry.id()

      assert page_windows[PageModule8] == [window_id]
    end

    test "gives a page reaching no query no windows", %{page_windows: page_windows} do
      assert page_windows[PageModule7] == []
    end

    test "answers for every page it was given", %{page_windows: page_windows} do
      answered_pages =
        page_windows
        |> Map.keys()
        |> Enum.sort()

      assert answered_pages == Enum.sort(Reflection.list_pages())
    end

    # What a client evaluates permissions against is grant rows, so a page checking them on the
    # client downloads them like any other rows it reads.
    test "gives a permission-checking page the grants window", %{call_graph: call_graph} do
      page_windows = build_page_windows([PageModule7], call_graph, [PageModule7])

      assert page_windows[PageModule7] == [Registry.id(Auth.grants_window())]
    end

    test "leaves the grants window out of a page that checks nothing", %{
      page_windows: page_windows
    } do
      refute Registry.id(Auth.grants_window()) in page_windows[PageModule7]
    end

    test "keeps a permission-checking page's own windows beside the grants window", %{
      call_graph: call_graph
    } do
      page_windows = build_page_windows([PageModule8], call_graph, [PageModule8])

      assert Registry.id(Auth.grants_window()) in page_windows[PageModule8]
      assert length(page_windows[PageModule8]) == 2
    end
  end

  # The gate reads the graph the bundles come from, so what registers the window is what actually
  # ships - not every mention of the check in the project.
  describe "pages_checking_permissions/2" do
    test "names a page whose template checks permissions", %{call_graph: call_graph} do
      pages = pages_checking_permissions(Reflection.list_pages(), call_graph)

      assert PageModule10 in pages
    end

    test "passes over a page that checks permissions only in a command handler", %{
      call_graph: call_graph
    } do
      pages = pages_checking_permissions(Reflection.list_pages(), call_graph)

      refute PageModule11 in pages
    end

    test "passes over a page that checks nothing", %{call_graph: call_graph} do
      pages = pages_checking_permissions(Reflection.list_pages(), call_graph)

      refute PageModule7 in pages
    end
  end

  describe "build_sync_constants/2" do
    setup %{call_graph: call_graph} do
      [sync_constants: build_sync_constants(Reflection.list_pages(), call_graph)]
    end

    test "collects the types the queries the given pages reach read", %{
      sync_constants: sync_constants
    } do
      assert MapSet.member?(sync_constants.entity_types, Entity15)
    end

    # An included type is one a client holds without any window being rooted in it - reaching it
    # is what puts its rows in the database, so it is named here like any other.
    test "collects the types those queries reach only through an include", %{
      sync_constants: sync_constants
    } do
      assert MapSet.member?(sync_constants.entity_types, Entity3)
      assert MapSet.member?(sync_constants.entity_types, Entity1)
    end

    # A type no query reads can never reach a client's database, so the build tells it nothing
    # about one - not its attributes, and not that it exists.
    test "leaves out a type no query reads", %{sync_constants: sync_constants} do
      refute MapSet.member?(sync_constants.entity_types, Entity12)
    end

    test "collects the argument names of the parameterized captures those components declare", %{
      sync_constants: sync_constants
    } do
      assert sync_constants.prop_params[ComponentModule24] == [entities: [:min_b]]
    end

    # A zero-arity capture binds nothing, so there is nothing to name - the client reads its
    # absence the same way it reads an empty list.
    test "leaves out a component declaring no parameterized capture", %{
      sync_constants: sync_constants
    } do
      refute Map.has_key?(sync_constants.prop_params, ComponentModule16)
    end

    # The attributes come from a fixture page reaching a query that orders a :string attribute -
    # what is asserted is the wiring from reachable queries to the attribute set, not the
    # derivation rules, which the registry's own suite pins.
    test "collects the attributes the queries those pages reach order by", %{
      sync_constants: sync_constants
    } do
      assert MapSet.member?(sync_constants.sort_key_attributes, {Entity15, :token})
    end
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
  end

  describe "build_module_digest_plt!/0" do
    test "adds module digest entries for modules that have a BEAM path" do
      assert %PLT{} = plt = build_module_digest_plt!()

      assert plt
             |> PLT.get!(Hologram.Reflection)
             |> is_integer()

      assert plt
             |> PLT.get!(Hologram.Compiler)
             |> is_integer()
    end

    test "doesn't add module digest entries for modules that don't have a BEAM path" do
      assert %PLT{} = plt = build_module_digest_plt!()
      assert PLT.get(plt, MyModule) == :error
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

      :ok
    end

    test "renders reachable function defs", %{ir_plt: ir_plt, runtime_mfas: runtime_mfas} do
      js =
        build_runtime_js(runtime_mfas, ir_plt, MapSet.new(), [], @empty_sync_constants, @js_dir)

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

    test "renders the clause heads of manually ported functions", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      js =
        build_runtime_js(runtime_mfas, ir_plt, MapSet.new(), [], @empty_sync_constants, @js_dir)

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
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      Application.put_env(:hologram, :client_error_overlay, true)
      Application.put_env(:hologram, :client_stacktraces, true)

      js =
        build_runtime_js(runtime_mfas, ir_plt, MapSet.new(), [], @empty_sync_constants, @js_dir)

      assert String.contains?(
               js,
               "globalThis.Hologram.config = {errorOverlay: true, stacktraces: true};"
             )
    end

    test "injects the client config when the presentation settings are disabled", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      Application.put_env(:hologram, :client_error_overlay, false)
      Application.put_env(:hologram, :client_stacktraces, false)

      js =
        build_runtime_js(runtime_mfas, ir_plt, MapSet.new(), [], @empty_sync_constants, @js_dir)

      assert String.contains?(
               js,
               "globalThis.Hologram.config = {errorOverlay: false, stacktraces: false};"
             )
    end

    test "registers the metadata of the modules it defines", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      Application.put_env(:hologram, :client_stacktraces, true)

      js =
        build_runtime_js(runtime_mfas, ir_plt, MapSet.new(), [], @empty_sync_constants, @js_dir)

      assert String.contains?(
               js,
               ~s/ERTS.registerModuleMetadata({"Access": {app: "elixir", file: "lib\/access.ex"/
             )
    end

    test "injects the versions of the applications the frames name", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      Application.put_env(:hologram, :client_stacktraces, true)

      app_versions = [hologram: "0.1.0", my_app: "9.8.7"]

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          MapSet.new(),
          app_versions,
          @empty_sync_constants,
          @js_dir
        )

      assert String.contains?(
               js,
               ~s/ERTS.appVersions = {"hologram": "0.1.0", "my_app": "9.8.7"};/
             )
    end

    test "quotes an application name that isn't a JavaScript identifier", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      Application.put_env(:hologram, :client_stacktraces, true)

      app_versions = [{:"my-app", "9.8.7"}]

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          MapSet.new(),
          app_versions,
          @empty_sync_constants,
          @js_dir
        )

      assert String.contains?(js, ~s/ERTS.appVersions = {"my-app": "9.8.7"};/)
    end

    # A build declaring NO entity types says `null` here, so no client of it asks to sync - which
    # cannot be shown from this suite, whose own model has entity types and whose reflection
    # nothing stubs. It is asserted in the umbrella app, which declares none.
    test "injects the model the bundle was built against", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      refute Reflection.list_entities() == []

      js =
        build_runtime_js(runtime_mfas, ir_plt, MapSet.new(), [], @empty_sync_constants, @js_dir)

      assert String.contains?(js, ~s/modelHash: "#{Model.hash()}", /)
    end

    # Every admitted attribute type in one entry, since a value's type is not recoverable from
    # the value itself - the client reads a date, an enum and a uuid apart only by what this says.
    test "injects the attribute types the client reads rows by", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      sync_constants = %{@empty_sync_constants | entity_types: MapSet.new([Entity4])}

      js = build_runtime_js(runtime_mfas, ir_plt, MapSet.new(), [], sync_constants, @js_dir)

      assert String.contains?(
               js,
               ~s/model: {"Hologram.Test.Fixtures.Entity.Module4":{"attributes":{"a":"date",/ <>
                 ~s/"b":"datetime","c":"enum","created_at":"datetime","d":"float","id":"uuid",/ <>
                 ~s/"updated_at":"datetime"},"relationships":{},"serverOnly":[],"sortKeys":[]}}/
             )
    end

    test "injects the relationships with their target types and cardinality", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      sync_constants = %{@empty_sync_constants | entity_types: MapSet.new([Entity3])}

      js = build_runtime_js(runtime_mfas, ir_plt, MapSet.new(), [], sync_constants, @js_dir)

      assert String.contains?(
               js,
               ~s/"relationships":{"a":{"toMany":true,"type":"Hologram.Test.Fixtures.Entity.Module2"},/ <>
                 ~s/"b":{"toMany":false,"type":"Hologram.Test.Fixtures.Entity.Module2"},/ <>
                 ~s/"c":{"toMany":false,"type":"Hologram.Test.Fixtures.Entity.Module1"}}/
             )
    end

    # The NAME travels while the value never does: a client that knows the attribute exists and
    # is not for it can say so, where one that never heard of it would answer nil.
    test "injects the names of the attributes a client may not have", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      sync_constants = %{@empty_sync_constants | entity_types: MapSet.new([Entity15])}

      js = build_runtime_js(runtime_mfas, ir_plt, MapSet.new(), [], sync_constants, @js_dir)

      assert String.contains?(js, ~s/"serverOnly":["secret_note","token"]/)
    end

    # A bundle carries the model of the types its own queries reach and no others: a type a
    # client can never hold is one it is told nothing about, its attribute names included.
    test "injects nothing about a type the client can never hold", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      sync_constants = %{@empty_sync_constants | entity_types: MapSet.new([Entity4])}

      js = build_runtime_js(runtime_mfas, ir_plt, MapSet.new(), [], sync_constants, @js_dir)

      refute String.contains?(js, "Hologram.Test.Fixtures.Entity.Module15")
      refute String.contains?(js, "secret_note")
    end

    # A type's sort keys ride in its own model entry: the ingest path already reads the entry to
    # decode the row, and every type named here is one the model names anyway.
    test "injects the sort keys the client computes at ingest", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      attributes = MapSet.new([{Entity15, :secret_note}, {Entity15, :token}])

      sync_constants = %{
        @empty_sync_constants
        | entity_types: MapSet.new([Entity15]),
          sort_key_attributes: attributes
      }

      js = build_runtime_js(runtime_mfas, ir_plt, MapSet.new(), [], sync_constants, @js_dir)

      assert String.contains?(js, ~s/"sortKeys":["secret_note","token"]/)
    end

    # A type nothing orders by carries an empty list rather than nothing at all - the ingest path
    # reads the field unconditionally.
    test "injects an empty sort-key list for a type no query orders by", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      sync_constants = %{@empty_sync_constants | entity_types: MapSet.new([Entity4])}

      js = build_runtime_js(runtime_mfas, ir_plt, MapSet.new(), [], sync_constants, @js_dir)

      assert String.contains?(js, ~s/"serverOnly":[],"sortKeys":[]}}/)
    end

    # A capture travels in the bundle and is called there, but an encoded function carries no
    # argument names - and those names are what each argument binds by.
    test "injects the argument names each query prop binds by", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      prop_params = %{ComponentModule24 => [entities: [:min_b, :max_b]]}
      sync_constants = %{@empty_sync_constants | prop_params: prop_params}

      js = build_runtime_js(runtime_mfas, ir_plt, MapSet.new(), [], sync_constants, @js_dir)

      # The names are written in argument order, not sorted: they are read positionally, so the
      # order IS the mapping from a prop to the argument it is passed as.
      assert String.contains?(
               js,
               ~s/propParams: {"Hologram.Test.Fixtures.Component.Module24":{"entities":["min_b","max_b"]}}/
             )
    end

    test "injects the wire format the bundle speaks" do
      js = build_runtime_js([], PLT.start(), MapSet.new(), [], @empty_sync_constants, @js_dir)

      assert String.contains?(js, ~s/protocolVersion: #{Frame.protocol_version()}};/)
    end

    test "injects no application versions when client stacktraces are disabled", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      Application.put_env(:hologram, :client_stacktraces, false)

      app_versions = [hologram: "0.1.0", my_app: "9.8.7"]

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          MapSet.new(),
          app_versions,
          @empty_sync_constants,
          @js_dir
        )

      assert String.contains?(js, "ERTS.appVersions = {};")
    end

    test "injects the client config when the error overlay is opted out of", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      Application.put_env(:hologram, :client_error_overlay, false)
      Application.put_env(:hologram, :client_stacktraces, true)

      js =
        build_runtime_js(runtime_mfas, ir_plt, MapSet.new(), [], @empty_sync_constants, @js_dir)

      assert String.contains?(
               js,
               "globalThis.Hologram.config = {errorOverlay: false, stacktraces: true};"
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

  test "create_page_entry_files/5", %{
    call_graph: call_graph,
    ir_plt: ir_plt,
    runtime_mfas: runtime_mfas
  } do
    opts = [
      js_dir: @js_dir,
      tmp_dir: Path.join([@tmp_dir, "tests", "compiler", "create_page_entry_files_5"])
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

  test "create_runtime_entry_file/6", %{ir_plt: ir_plt, runtime_mfas: runtime_mfas} do
    opts = [
      js_dir: @js_dir,
      tmp_dir: Path.join([@tmp_dir, "tests", "compiler", "create_runtime_entry_file_5"])
    ]

    clean_dir(opts[:tmp_dir])

    entry_file_path =
      create_runtime_entry_file(
        runtime_mfas,
        ir_plt,
        MapSet.new(),
        [],
        @empty_sync_constants,
        opts
      )

    assert entry_file_path == Path.join(opts[:tmp_dir], "runtime.entry.js")

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

    result = diff_module_digest_plts(old_plt, new_plt)

    keys =
      result
      |> Map.keys()
      |> Enum.sort()

    assert keys == [:added_modules, :edited_modules, :removed_modules]

    assert Enum.sort(result.added_modules) == [:module_2, :module_4]
    assert Enum.sort(result.removed_modules) == [:module_5, :module_7]
    assert Enum.sort(result.edited_modules) == [:module_3, :module_6]
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

  describe "maybe_load_module_digest_plt/1" do
    setup do
      test_tmp_dir = Path.join([@tmp_dir, "tests", "compiler", "maybe_load_module_digest_plt_1"])

      build_dir = Path.join(test_tmp_dir, "build")
      clean_dir(build_dir)

      dump_path = Path.join(build_dir, Reflection.module_digest_plt_dump_file_name())

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
          ~HOLO""
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
          ~HOLO""
        end
      end

      expected_msg =
        "page 'Hologram.CompilerTest.InlinePageModuleFixture2' doesn't have a layout module specified (use the layout/1 macro to fix it)"

      assert_raise Hologram.CompileError, expected_msg, fn ->
        validate_page_modules([Module11, InlinePageModuleFixture2])
      end
    end
  end

  # The validation rules live in QueryExtractor's own suite - what is asserted here is the wiring:
  # the components swept are the ones the given pages reach through the call graph.
  describe "validate_slot_bindings!/2" do
    test "passes when every reachable component binds declared slots", %{call_graph: call_graph} do
      assert validate_slot_bindings!(Reflection.list_pages(), call_graph) == :ok
    end

    test "raises when a reachable component binds an undeclared slot", %{call_graph: call_graph} do
      patched_call_graph =
        call_graph
        |> CallGraph.clone()
        |> CallGraph.add_edge(
          {PageModule7, :template, 0},
          {ComponentModule11, :template, 0}
        )

      expected_msg =
        "from_query for prop :entities in Hologram.Test.Fixtures.Component.Module11 binds argument :min_b - no like-named prop is declared"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_slot_bindings!([PageModule7], patched_call_graph)
      end
    end
  end
end
