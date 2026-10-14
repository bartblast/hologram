defmodule Hologram.CompilerTest do
  use Hologram.Test.BasicCase, async: false
  use Hologram.DB

  import Hologram.Compiler

  alias Hologram.Auth
  alias Hologram.Auth.RoleGrant
  alias Hologram.Commons.FileUtils
  alias Hologram.Commons.PLT
  alias Hologram.Commons.SystemUtils
  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Encoder
  alias Hologram.Compiler.IR
  alias Hologram.Entity.Model
  alias Hologram.Query
  alias Hologram.Query.Placeholder
  alias Hologram.Query.Registry
  alias Hologram.Query.Window
  alias Hologram.Reflection
  alias Hologram.Sync.Frame

  alias Hologram.Test.Fixtures.Component.Module1, as: ComponentModule1
  alias Hologram.Test.Fixtures.Component.Module11, as: ComponentModule11
  alias Hologram.Test.Fixtures.Component.Module13, as: ComponentModule13
  alias Hologram.Test.Fixtures.Component.Module14, as: ComponentModule14
  alias Hologram.Test.Fixtures.Component.Module15, as: ComponentModule15
  alias Hologram.Test.Fixtures.Component.Module16, as: ComponentModule16
  alias Hologram.Test.Fixtures.Component.Module17, as: ComponentModule17
  alias Hologram.Test.Fixtures.Component.Module18, as: ComponentModule18
  alias Hologram.Test.Fixtures.Component.Module19, as: ComponentModule19
  alias Hologram.Test.Fixtures.Component.Module20, as: ComponentModule20
  alias Hologram.Test.Fixtures.Component.Module24, as: ComponentModule24
  alias Hologram.Test.Fixtures.Component.Module28, as: ComponentModule28
  alias Hologram.Test.Fixtures.Component.Module29, as: ComponentModule29
  alias Hologram.Test.Fixtures.Entity.Module1, as: Entity1
  alias Hologram.Test.Fixtures.Entity.Module10, as: Entity10
  alias Hologram.Test.Fixtures.Entity.Module12, as: Entity12
  alias Hologram.Test.Fixtures.Entity.Module13, as: Entity13
  alias Hologram.Test.Fixtures.Entity.Module15, as: Entity15
  alias Hologram.Test.Fixtures.Entity.Module19, as: Entity19
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2
  alias Hologram.Test.Fixtures.Entity.Module3, as: Entity3
  alias Hologram.Test.Fixtures.Entity.Module4, as: Entity4
  alias Hologram.Test.Fixtures.Job.Module1, as: JobModule1
  alias Hologram.Test.Fixtures.Page.Module10, as: PageModule10
  alias Hologram.Test.Fixtures.Page.Module11, as: PageModule11
  alias Hologram.Test.Fixtures.Page.Module12, as: PageModule12
  alias Hologram.Test.Fixtures.Page.Module13, as: PageModule13
  alias Hologram.Test.Fixtures.Page.Module7, as: PageModule7
  alias Hologram.Test.Fixtures.Page.Module8, as: PageModule8
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyEntity

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
  alias Hologram.Test.Fixtures.Compiler.Module31
  alias Hologram.Test.Fixtures.Compiler.Module32
  alias Hologram.Test.Fixtures.Compiler.Module34
  alias Hologram.Test.Fixtures.Compiler.Module35
  alias Hologram.Test.Fixtures.Compiler.Module36
  alias Hologram.Test.Fixtures.Compiler.Module37
  alias Hologram.Test.Fixtures.Compiler.Module38
  alias Hologram.Test.Fixtures.Compiler.Module39
  alias Hologram.Test.Fixtures.Compiler.Module4
  alias Hologram.Test.Fixtures.Compiler.Module40
  alias Hologram.Test.Fixtures.Compiler.Module8
  alias Hologram.Test.Fixtures.Compiler.Module9
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module1, as: QueryExtractorModule1

  @root_dir Reflection.root_dir()
  @assets_dir Path.join(@root_dir, "assets")
  @js_dir Path.join(@assets_dir, "js")
  @erlang_js_dir Path.join(@js_dir, "erlang")

  @fixtures_compiler_dir Path.join(@fixtures_dir, "compiler")
  @empty_sync_constants %{
    entity_types: MapSet.new(),
    model_hash: "my_model_hash",
    permission_checking?: false,
    prop_params: %{}
  }

  # A statement setting the client's data layer constants, as the runtime script takes it rendered
  # (see build_sync_constants_js/1), for the tests of what the script carries besides.
  @empty_sync_constants_js ~s/globalThis.Hologram.sync = {model: {}, modelHash: "", propParams: {}, protocolVersion: 1};/
  @tmp_dir Reflection.tmp_dir()

  # Bundles an entry file that runs the given JavaScript, in a tmp dir of the given name, with a
  # js dir of its own, and returns the inputs the bundle recorded. Each file written through
  # write_js_input/3 gets an mtime in the past, so that none counts as written during the bundling.
  defp bundle_js_inputs(test_subdir, entry_js) do
    node_modules_path = Path.join([@root_dir, "assets", "node_modules"])
    test_tmp_dir = Path.join([@tmp_dir, "tests", "compiler", test_subdir])

    opts = [
      esbuild_bin_path: esbuild_bin_path(node_modules_path),
      js_dir: Path.join(test_tmp_dir, "hologram_js"),
      node_modules_path: node_modules_path,
      static_dir: Path.join(test_tmp_dir, "static"),
      tmp_dir: Path.join(test_tmp_dir, "tmp")
    ]

    File.mkdir_p!(opts[:static_dir])
    File.mkdir_p!(opts[:tmp_dir])

    entry_file_path = Path.join(opts[:tmp_dir], "MyPage.entry.js")
    File.write!(entry_file_path, entry_js)

    %{js_inputs: js_inputs} = bundle(MyPage, entry_file_path, "page", opts)

    js_inputs
  end

  # The options to bundle with in a tmp dir of the given name, which is left empty but for its
  # static dir. The tmp dir is relative to the working dir, so that an entry file in it takes the
  # same share of the command line esbuild is started with on every machine.
  defp bundling_opts(test_subdir) do
    node_modules_path = Path.join([@root_dir, "assets", "node_modules"])
    tmp_dir = Path.join(["tmp", "tests", "compiler", test_subdir])

    opts = [
      esbuild_bin_path: esbuild_bin_path(node_modules_path),
      node_modules_path: node_modules_path,
      static_dir: Path.join(tmp_dir, "static"),
      tmp_dir: tmp_dir
    ]

    clean_dir(tmp_dir)
    File.mkdir!(opts[:static_dir])

    opts
  end

  # The windows of the given pages, derived the way the compile task derives them: each page's reach
  # on the given graph folded into what the data layer keeps, and the queries of the components the
  # pages reach.
  defp derive_page_windows(pages, call_graph, module_info_plt, permission_checking_pages) do
    reach_by_page =
      pages
      |> list_reach_by_page(call_graph)
      |> build_kept_page_reach(permission_checking_pages, module_info_plt)

    entity_types = Reflection.list_entities(module_info_plt)

    component_queries =
      reach_by_page
      |> Enum.flat_map(fn {_page_module, reach} -> reach.components end)
      |> Enum.uniq()
      |> extract_component_queries(entity_types)

    build_page_windows(reach_by_page, component_queries, module_info_plt)
  end

  # What every page of the test build reaches on the given graph, as the compile task lists it for
  # the data layer.
  defp page_reach(call_graph) do
    list_reach_by_page(Reflection.list_pages(), call_graph)
  end

  # Runs the function and returns its result with the number of times esbuild was run.
  defp count_esbuild_runs(fun) do
    mfa = {SystemUtils, :cmd_cross_platform, 3}

    # A call count is kept only for a module that is loaded when the counting starts.
    Code.ensure_loaded!(SystemUtils)
    :erlang.trace_pattern(mfa, true, [:call_count])

    try do
      result = fun.()
      {:call_count, count} = :erlang.trace_info(mfa, :call_count)

      {result, count}
    after
      :erlang.trace_pattern(mfa, false, [:call_count])
    end
  end

  # Runs the function with call counts on the one-argument protocol, protocol implementation and
  # JS import checks, which consult a module's code path, and returns its result with the number
  # of such checks.
  defp count_module_self_checks(fun) do
    mfas = [
      {Reflection, :protocol?, 1},
      {Reflection, :protocol_implementation, 1},
      {Reflection, :js_imports?, 1}
    ]

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

  # Writes the given number of chunk entry files, each with a content of its own, into the tmp dir
  # of the given options, and returns them as bundle_chunks/2 takes them: the entry names are
  # "00000001", "00000002" and so on.
  defp create_chunk_entries(count, opts) do
    Enum.map(1..count, fn index ->
      entry_name =
        index
        |> Integer.to_string()
        |> String.pad_leading(8, "0")

      entry_file_path = Path.join(opts[:tmp_dir], "chunk-#{entry_name}.entry.js")
      File.write!(entry_file_path, "export const myVar = #{index};\n")

      {entry_name, entry_file_path}
    end)
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

  # The runtime's MFAs without the ones of modules that declare JS imports: the test build's runtime
  # carries a component that does (see Mix.Tasks.Compile.HologramTest), which a test that sets out
  # the imports itself leaves out.
  defp reject_js_import_mfas(mfas) do
    Enum.reject(mfas, fn {module, _function, _arity} -> Reflection.js_imports?(module) end)
  end

  # A copy of Hologram's JavaScript sources and package.json, so that a test can edit them.
  defp setup_bundle_inputs_test(test_subdir) do
    on_exit(fn -> Application.delete_env(:hologram, :client_stacktraces) end)

    test_tmp_dir = Path.join([@tmp_dir, "tests", "compiler", test_subdir])
    assets_dir = Path.join(test_tmp_dir, "assets")
    js_dir = Path.join(assets_dir, "js")

    clean_dir(test_tmp_dir)
    File.mkdir_p!(assets_dir)
    File.cp_r!(@js_dir, js_dir)
    package_json_path = Path.join(assets_dir, "package.json")

    @assets_dir
    |> Path.join("package.json")
    |> File.cp!(package_json_path)

    [opts: [assets_dir: assets_dir, js_dir: js_dir]]
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

  # A module info PLT holding Module1, Module2, Module3 and Hologram.JS, the module of the manually
  # ported MFAs, so that the modules outside it are the ones a lister leaves out.
  defp small_module_info_plt do
    info = %{digest: 1, mtime: 1, size: 1}

    PLT.start()
    |> PLT.put(Module1, info)
    |> PLT.put(Module2, info)
    |> PLT.put(Module3, info)
    |> PLT.put(Hologram.JS, info)
  end

  defp write_js_input(test_tmp_dir, relative_path, content) do
    path = Path.join(test_tmp_dir, relative_path)

    path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(path, content)
    File.touch!(path, System.os_time(:second) - 10)

    path
  end

  setup_all do
    ir_plt = build_ir_plt()
    call_graph = build_call_graph(ir_plt)

    [
      call_graph: call_graph,
      ir_plt: ir_plt,
      module_info_plt: CallGraph.module_info_plt(call_graph),
      runtime_mfas: CallGraph.list_runtime_mfas(call_graph)
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

  describe "app_versions_changed?/2" do
    setup do
      [diff: %{added_modules: [], removed_modules: [], edited_modules: []}]
    end

    test "an added module", %{diff: diff} do
      assert app_versions_changed?(%{diff | added_modules: [Module1]}, :hologram)
    end

    test "an edited module of another application", %{diff: diff} do
      assert app_versions_changed?(%{diff | edited_modules: [Enum]}, :hologram)
    end

    test "an edited module of no application", %{diff: diff} do
      assert app_versions_changed?(%{diff | edited_modules: [:no_such_module]}, :hologram)
    end

    test "an empty diff", %{diff: diff} do
      refute app_versions_changed?(diff, :hologram)
    end

    test "a removed module", %{diff: diff} do
      assert app_versions_changed?(%{diff | removed_modules: [Module1]}, :hologram)
    end

    test "edited modules of the project's application only", %{diff: diff} do
      refute app_versions_changed?(%{diff | edited_modules: [Compiler, Reflection]}, :hologram)
    end
  end

  describe "build_app_versions/1" do
    test "names the applications of the modules the graph holds" do
      call_graph =
        CallGraph.start()
        |> CallGraph.add_vertex(Enum)
        |> CallGraph.add_vertex({:lists, :reverse, 1})

      assert build_app_versions(call_graph) == [
               elixir: to_string(Application.spec(:elixir, :vsn)),
               stdlib: to_string(Application.spec(:stdlib, :vsn))
             ]
    end

    test "names the application of the function a dynamic call was found in" do
      site = {:dynamic_call, {Enum, :map, 2}, :__struct__, 0, :open}
      call_graph = CallGraph.add_vertex(CallGraph.start(), site)

      assert build_app_versions(call_graph) == [
               elixir: to_string(Application.spec(:elixir, :vsn))
             ]
    end
  end

  describe "build_page_js/5" do
    setup %{call_graph: call_graph, runtime_mfas: runtime_mfas} do
      call_graph_without_runtime_mfas =
        call_graph
        |> CallGraph.clone()
        |> CallGraph.remove_runtime_mfas!(runtime_mfas)

      # A PLT per test, so one test's warm cache can never stand in for another's encoding.
      [
        analyses: PLT.start(),
        encode_plt: PLT.start(),
        graph: CallGraph.get_graph(call_graph_without_runtime_mfas),
        module_info_plt: CallGraph.module_info_plt(call_graph)
      ]
    end

    test "has both Erlang and Elixir function defs", %{
      encode_plt: encode_plt,
      graph: graph,
      ir_plt: ir_plt,
      module_info_plt: module_info_plt,
      analyses: analyses
    } do
      mfas =
        CallGraph.list_page_mfas(
          graph,
          Module24,
          analyses,
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

      js_fragment_1 = ~s/globalThis.Hologram.pendingScripts.push({/
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
      analyses: analyses
    } do
      mfas =
        CallGraph.list_page_mfas(
          graph,
          Module25,
          analyses,
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

      js_fragment_1 = ~s/globalThis.Hologram.pendingScripts.push({/
      js_fragment_2 = ~s/Interpreter.defineElixirFunction/
      js_fragment_3 = ~s/Interpreter.defineErlangFunction/

      assert String.contains?(result, js_fragment_1)
      assert String.contains?(result, js_fragment_2)
      refute String.contains?(result, js_fragment_3)
    end

    test "leaves its function defs for the runtime to define, under its own digest", %{
      ir_plt: ir_plt
    } do
      mfas = [{Module22, :my_fun, 0}]

      result = build_page_js(mfas, ir_plt, PLT.start(), MapSet.new(), js_dir: @js_dir)

      js_fragment_1 = "globalThis.Hologram.pendingScripts ??= [];"
      js_fragment_2 = "globalThis.Hologram.pendingScripts.push({"

      js_fragment_3 =
        ~S"digest: new URL(document.currentScript.src).pathname.match(/-([^-]+)\.js$/)[1],"

      js_fragment_4 = "define: (deps) => {"
      js_fragment_5 = ~s/document.dispatchEvent(new CustomEvent("hologram:scriptLoaded"));/

      js_fragment_6 =
        ~s/console.debug("Hologram: page script executed in", PerformanceTimer.diff(startTime));/

      assert String.contains?(result, js_fragment_1)
      assert String.contains?(result, js_fragment_2)
      assert String.contains?(result, js_fragment_3)
      assert String.contains?(result, js_fragment_4)
      assert String.contains?(result, js_fragment_5)
      assert String.ends_with?(result, js_fragment_6)

      refute String.contains?(result, "pageReachableFunctionDefs")
      refute String.contains?(result, "pageScriptLoaded")
    end

    test "no JS imports", %{
      encode_plt: encode_plt,
      graph: graph,
      ir_plt: ir_plt,
      module_info_plt: module_info_plt,
      analyses: analyses
    } do
      mfas =
        CallGraph.list_page_mfas(
          graph,
          Module11,
          analyses,
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
      analyses: analyses
    } do
      mfas =
        CallGraph.list_page_mfas(
          graph,
          Module19,
          analyses,
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
      analyses: analyses
    } do
      mfas =
        CallGraph.list_page_mfas(
          graph,
          Module21,
          analyses,
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
      analyses: analyses
    } do
      mfas =
        CallGraph.list_page_mfas(
          graph,
          Module23,
          analyses,
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
      analyses: analyses
    } do
      mfas =
        CallGraph.list_page_mfas(
          graph,
          Module23,
          analyses,
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

    test "asks no module whether it is a protocol or an implementation, or declares JS imports, when given the module info PLT",
         %{
           encode_plt: encode_plt,
           graph: graph,
           ir_plt: ir_plt,
           module_info_plt: module_info_plt,
           analyses: analyses
         } do
      mfas =
        CallGraph.list_page_mfas(
          graph,
          Module23,
          analyses,
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

  describe "build_bundle_inputs/1" do
    setup do
      setup_bundle_inputs_test("build_bundle_inputs_1")
    end

    test "changes when a JavaScript source changes", %{opts: opts} do
      bundle_inputs = build_bundle_inputs(opts)
      js_source_path = Path.join(opts[:js_dir], "hologram.mjs")
      File.write!(js_source_path, "\n", [:append])

      assert build_bundle_inputs(opts).js_sources != bundle_inputs.js_sources
    end

    test "changes when package.json changes", %{opts: opts} do
      bundle_inputs = build_bundle_inputs(opts)
      package_json_path = Path.join(opts[:assets_dir], "package.json")
      File.write!(package_json_path, "\n", [:append])

      assert build_bundle_inputs(opts).package_json_digest != bundle_inputs.package_json_digest
    end

    test "is equal for two calls with nothing changed", %{opts: opts} do
      assert build_bundle_inputs(opts) == build_bundle_inputs(opts)
    end

    test "leaves out directories", %{opts: opts} do
      %{js_sources: js_sources} = build_bundle_inputs(opts)

      refute Enum.any?(js_sources, fn {path, _mtime, _size} -> path == "erlang" end)
    end

    test "lists every JavaScript source under the js dir with its mtime and size, sorted", %{
      opts: opts
    } do
      %{js_sources: js_sources} = build_bundle_inputs(opts)

      file_paths =
        opts[:js_dir]
        |> Path.join("**/*")
        |> Path.wildcard()
        |> Enum.filter(&File.regular?/1)

      %File.Stat{mtime: mtime, size: size} =
        opts[:js_dir]
        |> Path.join("hologram.mjs")
        |> File.stat!(time: :posix)

      assert {"hologram.mjs", mtime, size} in js_sources

      assert Enum.any?(js_sources, fn {path, _mtime, _size} ->
               String.starts_with?(path, "erlang/")
             end)

      assert length(js_sources) == length(file_paths)
      assert js_sources == Enum.sort(js_sources)
    end

    test "names no module", %{opts: opts} do
      refute opts
             |> build_bundle_inputs()
             |> Map.has_key?(:hologram_modules)
    end

    test "names the client stack traces setting", %{opts: opts} do
      Application.put_env(:hologram, :client_stacktraces, true)
      assert build_bundle_inputs(opts).client_stacktraces? == true

      Application.put_env(:hologram, :client_stacktraces, false)
      assert build_bundle_inputs(opts).client_stacktraces? == false
    end
  end

  describe "build_bundle_inputs/2" do
    setup do
      setup_bundle_inputs_test("build_bundle_inputs_2")
    end

    test "adds the digests of Hologram's modules to the inputs that need no module", %{
      module_info_plt: module_info_plt,
      opts: opts
    } do
      bundle_inputs = build_bundle_inputs(module_info_plt, opts)

      assert Map.delete(bundle_inputs, :hologram_modules) == build_bundle_inputs(opts)
      assert bundle_inputs.hologram_modules != []
    end

    test "leaves out the :hologram app's modules compiled from outside Hologram's lib dir", %{
      module_info_plt: module_info_plt,
      opts: opts
    } do
      %{hologram_modules: hologram_modules} = build_bundle_inputs(module_info_plt, opts)
      hologram_module_names = Enum.map(hologram_modules, fn {module, _digest} -> module end)

      # A test fixture, compiled into the :hologram app from test/elixir/support.
      assert Module18 in Application.spec(:hologram, :modules)
      assert PLT.member?(module_info_plt, Module18)
      refute Module18 in hologram_module_names

      assert Enum.all?(hologram_module_names, fn module ->
               module_info_plt
               |> PLT.get!(module)
               |> Map.fetch!(:source_path)
               |> String.starts_with?(Path.join(@root_dir, "lib"))
             end)
    end

    test "lists Hologram's modules with their module info digests, sorted", %{
      module_info_plt: module_info_plt,
      opts: opts
    } do
      %{hologram_modules: hologram_modules} = build_bundle_inputs(module_info_plt, opts)
      hologram_app_modules = Application.spec(:hologram, :modules)

      assert {Compiler, PLT.get!(module_info_plt, Compiler).digest} in hologram_modules
      assert hologram_modules == Enum.sort(hologram_modules)

      assert Enum.all?(hologram_modules, fn {module, _digest} ->
               module in hologram_app_modules
             end)
    end
  end

  test "build_call_graph/0" do
    assert %CallGraph{} = call_graph = build_call_graph()

    assert CallGraph.has_vertex?(call_graph, {Compiler, :build_call_graph, 1})
  end

  describe "build_page_windows/3" do
    setup %{call_graph: call_graph, module_info_plt: module_info_plt} do
      page_windows = derive_page_windows(Reflection.list_pages(), call_graph, module_info_plt, [])

      [page_windows: page_windows]
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
    test "gives a permission-checking page the grants window", %{
      call_graph: call_graph,
      module_info_plt: module_info_plt
    } do
      page_windows =
        derive_page_windows([PageModule7], call_graph, module_info_plt, [PageModule7])

      assert page_windows[PageModule7] == [Registry.id(Auth.grants_window())]
    end

    test "leaves the grants window out of a page that checks nothing", %{
      page_windows: page_windows
    } do
      refute Registry.id(Auth.grants_window()) in page_windows[PageModule7]
    end

    test "keeps a permission-checking page's own windows beside the grants window", %{
      call_graph: call_graph,
      module_info_plt: module_info_plt
    } do
      page_windows =
        derive_page_windows([PageModule8], call_graph, module_info_plt, [PageModule8])

      assert Registry.id(Auth.grants_window()) in page_windows[PageModule8]
      assert length(page_windows[PageModule8]) == 2
    end

    # The grant entity is an entity type like any other, so a page's own query can derive the very
    # window the permission check downloads - and then it is named once rather than subscribed to
    # twice.
    test "names the grants window once for a page whose own query derives it", %{
      call_graph: call_graph,
      module_info_plt: module_info_plt
    } do
      page_windows =
        derive_page_windows([PageModule12], call_graph, module_info_plt, [PageModule12])

      assert page_windows[PageModule12] == [Registry.id(Auth.grants_window())]
    end

    # No user entity type, no grant store: a page checking permissions has nothing to check them
    # against.
    test "leaves the grants window out of a checking page when the data model designates no user entity type",
         %{call_graph: call_graph, module_info_plt: module_info_plt} do
      items =
        module_info_plt
        |> PLT.get_all()
        |> Enum.map(fn {module, info} -> {module, Map.put(info, :user_entity?, false)} end)

      plt_without_user_entity = PLT.start(items: items)

      page_windows =
        derive_page_windows([PageModule7], call_graph, plt_without_user_entity, [PageModule7])

      assert page_windows[PageModule7] == []
    end
  end

  # The gate reads the graph the bundles come from, so what registers the window is what actually
  # ships - not every mention of the check in the project.
  # can?/3 and the grant verbs read grant rows in the browser, which is what makes a page a
  # permission checker - and every one of them is hand-ported, or a page reaching it would have the
  # verb's server call tree transpiled into its bundle. Two lists in two modules; this ties them.
  test "every permission MFA is a manually ported one" do
    assert permission_mfas() -- CallGraph.manually_ported_elixir_mfas() == []
  end

  describe "operation_asks/2" do
    # The offending asks are built as IR rather than as file fixtures, because a file fixture
    # would refuse the build in the compile.hologram Mix task tests, which compile the whole
    # project. The module's name has to exist as an atom before IR.for_code/2 resolves it, which
    # spelling it here as a literal guarantees.
    @asker Hologram.Test.Fixtures.Compiler.OperationAsker

    defp asker_plt(code) do
      PLT.put(PLT.start(), @asker, IR.for_code(code, %Context{}))
    end

    defp asker_graph(edges) do
      graph = CallGraph.start()

      Enum.each(edges, fn {function, arity, target} ->
        CallGraph.add_edge(graph, {@asker, function, arity}, target)
      end)

      graph
    end

    test "reads every ask of every caller, sorted by the calling function" do
      plt =
        asker_plt(~S"""
        defmodule Hologram.Test.Fixtures.Compiler.OperationAsker do
          def h(user, operation, entity), do: Hologram.Auth.can?(user, operation, entity)
          def f(user, entity), do: Hologram.Auth.can?(user, :nope, entity)
          def g(user, entity), do: Hologram.Auth.can?(user, {:grant_role, :editr}, entity)
        end
        """)

      graph =
        asker_graph([
          {:f, 2, {Hologram.Auth, :can?, 3}},
          {:g, 2, {Hologram.Auth, :can?, 3}},
          {:h, 3, {Hologram.Auth, :can?, 3}}
        ])

      assert operation_asks(graph, plt) == [
               %{line: 3, mfa: {@asker, :f, 2}, operation: :nope},
               %{line: 4, mfa: {@asker, :g, 2}, operation: {:grant_role, :editr}},
               %{line: 2, mfa: {@asker, :h, 3}, operation: :dynamic}
             ]
    end

    test "reads the operation a claim stage names" do
      plt =
        asker_plt(~S"""
        defmodule Hologram.Test.Fixtures.Compiler.OperationAsker do
          def f(entity), do: Hologram.Query.authorize(entity, :publsh)
        end
        """)

      graph = asker_graph([{:f, 1, {Hologram.Query, :authorize, 2}}])

      assert operation_asks(graph, plt) == [
               %{line: 2, mfa: {@asker, :f, 1}, operation: :publsh}
             ]
    end

    test "reads the authorize option of a job enqueue" do
      plt =
        asker_plt(~S"""
        defmodule Hologram.Test.Fixtures.Compiler.OperationAsker do
          def f(values), do: Hologram.Job.create(Hologram.Test.Fixtures.Job.Module1, values, authorize: :genrate)
          def g(values), do: Hologram.Job.create!(Hologram.Test.Fixtures.Job.Module1, values, authorize: :genrate)
        end
        """)

      graph =
        asker_graph([
          {:f, 1, {Hologram.Job, :create, 3}},
          {:g, 1, {Hologram.Job, :create!, 3}}
        ])

      assert operation_asks(graph, plt) == [
               %{line: 2, mfa: {@asker, :f, 1}, operation: :genrate},
               %{line: 3, mfa: {@asker, :g, 1}, operation: :genrate}
             ]
    end

    test "passes over an enqueue claiming the server's authority" do
      plt =
        asker_plt(~S"""
        defmodule Hologram.Test.Fixtures.Compiler.OperationAsker do
          def f(values), do: Hologram.Job.create(Hologram.Test.Fixtures.Job.Module1, values, trust: true)
        end
        """)

      graph = asker_graph([{:f, 1, {Hologram.Job, :create, 3}}])

      assert operation_asks(graph, plt) == []
    end

    test "marks an enqueue whose options are computed as dynamic" do
      plt =
        asker_plt(~S"""
        defmodule Hologram.Test.Fixtures.Compiler.OperationAsker do
          def f(values, opts), do: Hologram.Job.create(Hologram.Test.Fixtures.Job.Module1, values, opts)
        end
        """)

      graph = asker_graph([{:f, 2, {Hologram.Job, :create, 3}}])

      assert operation_asks(graph, plt) == [
               %{line: 2, mfa: {@asker, :f, 2}, operation: :dynamic}
             ]
    end

    test "skips a caller absent from the IR PLT" do
      graph = asker_graph([{:f, 2, {Hologram.Auth, :can?, 3}}])

      assert operation_asks(graph, PLT.start()) == []
    end

    test "reads a fixture page's template through the project's own graph", %{
      call_graph: call_graph,
      ir_plt: ir_plt
    } do
      asks = operation_asks(call_graph, ir_plt)

      assert Enum.any?(asks, &match?(%{mfa: {PageModule10, :template, 0}, operation: :read}, &1))
      assert Enum.any?(asks, &match?(%{mfa: {PageModule11, :command, 3}, operation: :read}, &1))

      assert Enum.any?(
               asks,
               &match?(
                 %{mfa: {Hologram.DB.Writer, :evaluate_operation!, 2}, operation: :dynamic},
                 &1
               )
             )
    end
  end

  describe "pages_checking_permissions/1" do
    test "names a page whose template checks permissions", %{call_graph: call_graph} do
      pages = pages_checking_permissions(page_reach(call_graph))

      assert PageModule10 in pages
    end

    test "passes over a page that checks permissions only in a command handler", %{
      call_graph: call_graph
    } do
      pages = pages_checking_permissions(page_reach(call_graph))

      refute PageModule11 in pages
    end

    test "passes over a page that checks nothing", %{call_graph: call_graph} do
      pages = pages_checking_permissions(page_reach(call_graph))

      refute PageModule7 in pages
    end

    # No fixture page calls the grant verbs in its client code, deliberately: until the verbs are
    # registered as ported, a page reaching one would have its server call tree transpiled into
    # its bundle. The edge is added to a clone instead - a page's template is client code - and
    # can?/3 is taken OUT of that clone first: the verbs call it, so in the real graph a page
    # reaching a verb reaches can? too and would qualify under the old rule alone. Once the verbs
    # are ported their subtree is pruned from every build, which is the state this pins.
    test "names a page whose client code grants a role", %{call_graph: call_graph} do
      graph = CallGraph.clone(call_graph)
      CallGraph.remove_vertex(graph, {Hologram.Auth, :can?, 3})
      CallGraph.add_edge(graph, {PageModule7, :template, 0}, {Hologram.Auth, :grant_role, 3})

      assert PageModule7 in pages_checking_permissions(page_reach(graph))
    end

    test "names a page whose client code revokes a role", %{call_graph: call_graph} do
      graph = CallGraph.clone(call_graph)
      CallGraph.remove_vertex(graph, {Hologram.Auth, :can?, 3})
      CallGraph.add_edge(graph, {PageModule7, :template, 0}, {Hologram.Auth, :revoke_role, 3})

      assert PageModule7 in pages_checking_permissions(page_reach(graph))
    end
  end

  describe "build_queries/2" do
    setup do
      [entity_types: Reflection.list_entities()]
    end

    test "collects the entries, prop params and windows of the given components", %{
      entity_types: entity_types
    } do
      component_queries =
        extract_component_queries([QueryExtractorModule1, ComponentModule11], entity_types)

      queries = build_queries(component_queries, entity_types)

      module_1_term =
        Entity2
        |> filter(a: true)
        |> order_by(:c)
        |> Query.normalize()

      module_11_term =
        Entity2
        |> filter(b: {:>=, %Placeholder{name: :min_b}})
        |> Query.normalize()

      expected_entries = Registry.build([module_1_term, module_11_term])

      assert queries.entries == expected_entries
      assert queries.prop_params == %{{ComponentModule11, :entities} => [:min_b]}
    end

    # The grants window rides with every build's windows, whether or not a page subscribes to it -
    # the build decides who asks, this is only where an id resolves back to a term.
    test "registers the grants window beside the windows the queries download", %{
      entity_types: entity_types
    } do
      component_queries = extract_component_queries([QueryExtractorModule1], entity_types)
      queries = build_queries(component_queries, entity_types)

      grants_window = Auth.grants_window()

      assert queries.windows[Registry.id(grants_window)] == grants_window
    end

    # No user entity type, no grant store: there is no table to evaluate the window against.
    test "registers no grants window when the given entity types hold no role grant store", %{
      entity_types: entity_types
    } do
      component_queries = extract_component_queries([QueryExtractorModule1], entity_types)
      queries = build_queries(component_queries, entity_types -- [RoleGrant])

      refute Map.has_key?(queries.windows, Registry.id(Auth.grants_window()))
    end

    test "leaves out a component declaring no parameterized capture", %{
      entity_types: entity_types
    } do
      component_queries = extract_component_queries([QueryExtractorModule1], entity_types)
      queries = build_queries(component_queries, entity_types)

      assert queries.prop_params == %{}
    end

    test "collects a registered query reading a type with server-only attributes it does not reference",
         %{entity_types: entity_types} do
      component_queries = extract_component_queries([ComponentModule20], entity_types)
      queries = build_queries(component_queries, entity_types)

      assert map_size(queries.entries) == 1
    end

    test "raises for a registered query whose root type declares no allow lines", %{
      entity_types: entity_types
    } do
      expected_msg =
        "the registered query in Hologram.Test.Fixtures.Component.Module15 reads " <>
          "Hologram.Test.Fixtures.Entity.Module1, which declares no allow lines - " <>
          "default deny returns no rows to any session. Add allow lines, or drop the query."

      component_queries = extract_component_queries([ComponentModule15], entity_types)

      assert_error Hologram.CompileError, expected_msg, fn ->
        build_queries(component_queries, entity_types)
      end
    end

    test "raises for a registered query whose include target declares no allow lines", %{
      entity_types: entity_types
    } do
      expected_msg =
        "the registered query in Hologram.Test.Fixtures.Component.Module16 includes " <>
          "Hologram.Test.Fixtures.Entity.Module1, which declares no allow lines - " <>
          "default deny leaves the embed empty in every row. Add allow lines, or drop the include."

      component_queries = extract_component_queries([ComponentModule16], entity_types)

      assert_error Hologram.CompileError, expected_msg, fn ->
        build_queries(component_queries, entity_types)
      end
    end

    test "raises for a registered query filtering on a server-only attribute", %{
      entity_types: entity_types
    } do
      expected_msg =
        "the registered query in Hologram.Test.Fixtures.Component.Module17 filters or orders on " <>
          "server_only attributes (Hologram.Test.Fixtures.Entity.Module15 :token) - the client " <>
          "never holds those values, so it could not evaluate the reference locally. Drop the " <>
          "reference, or read the rows through the trusted backend API."

      component_queries = extract_component_queries([ComponentModule17], entity_types)

      assert_error Hologram.CompileError, expected_msg, fn ->
        build_queries(component_queries, entity_types)
      end
    end

    test "raises for a registered query ordering on a server-only attribute", %{
      entity_types: entity_types
    } do
      expected_msg =
        "the registered query in Hologram.Test.Fixtures.Component.Module18 filters or orders on " <>
          "server_only attributes (Hologram.Test.Fixtures.Entity.Module15 :token) - the client " <>
          "never holds those values, so it could not evaluate the reference locally. Drop the " <>
          "reference, or read the rows through the trusted backend API."

      component_queries = extract_component_queries([ComponentModule18], entity_types)

      assert_error Hologram.CompileError, expected_msg, fn ->
        build_queries(component_queries, entity_types)
      end
    end

    test "raises for a registered query filtering on a server-only attribute inside an include",
         %{
           entity_types: entity_types
         } do
      expected_msg =
        "the registered query in Hologram.Test.Fixtures.Component.Module19 filters or orders on " <>
          "server_only attributes (Hologram.Test.Fixtures.Entity.Module15 :token) - the client " <>
          "never holds those values, so it could not evaluate the reference locally. Drop the " <>
          "reference, or read the rows through the trusted backend API."

      component_queries = extract_component_queries([ComponentModule19], entity_types)

      assert_error Hologram.CompileError, expected_msg, fn ->
        build_queries(component_queries, entity_types)
      end
    end

    test "raises for a registered query claiming the server's authority", %{
      entity_types: entity_types
    } do
      expected_msg =
        "the registered query in Hologram.Test.Fixtures.Component.Module28 claims the server's " <>
          "authority with trust() - a component's query is read for the session user on both " <>
          "tiers, so it cannot claim another. Drop trust(), or read through the backend API in " <>
          "a command."

      component_queries = extract_component_queries([ComponentModule28], entity_types)

      assert_error Hologram.CompileError, expected_msg, fn ->
        build_queries(component_queries, entity_types)
      end
    end
  end

  describe "build_queries_plt/2" do
    test "holds the entries, prop params and windows, and dumps beside the other build artifacts" do
      entity_types = Reflection.list_entities()

      queries =
        [ComponentModule11]
        |> extract_component_queries(entity_types)
        |> build_queries(entity_types)

      opts = [build_dir: "/my_build_dir"]

      {plt, dump_path} = build_queries_plt(queries, opts)

      assert PLT.get_all(plt) == queries
      assert dump_path == "/my_build_dir/queries.plt"
    end
  end

  describe "build_sync_constants/3" do
    setup %{call_graph: call_graph, module_info_plt: module_info_plt} do
      [sync_constants: build_sync_constants(page_reach(call_graph), module_info_plt)]
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

    # A client constructs and validates entities as well as reading them, and the type it
    # constructs is the one it needs the declarations of. PageModule13 holds a Module4 in an
    # action and no query anywhere reads that type, so mentioning it is the only way it can be
    # here - and Module4 declares no policy, so the policied set cannot be carrying it either.
    test "collects a type the given pages mention without querying", %{
      sync_constants: sync_constants
    } do
      assert MapSet.member?(sync_constants.entity_types, Entity4)
    end

    # A type nothing reads and nothing mentions can never reach a client's database or be built
    # there, so the build tells it nothing about one - not its attributes, and not that it exists.
    # That is what keeps an app's other tables out of a file every page load serves.
    test "leaves out a type no query reads and no page mentions", %{
      sync_constants: sync_constants
    } do
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

    # The grant type reaches the model by being CHECKED rather than by being queried - its window
    # is registered rather than extracted - so a client checking permissions locally would
    # otherwise hold rows of a type the model never described. Both cases run over one page that
    # queries no grants, so the flag is the only thing that differs between them.
    test "names the grant type when a page checks permissions on the client", %{
      call_graph: call_graph,
      module_info_plt: module_info_plt
    } do
      reach_by_page = list_reach_by_page([PageModule8], call_graph)
      sync_constants = build_sync_constants(reach_by_page, module_info_plt, true)

      assert MapSet.member?(sync_constants.entity_types, RoleGrant)
    end

    test "leaves the grant type out when no page checks permissions on the client", %{
      call_graph: call_graph,
      module_info_plt: module_info_plt
    } do
      reach_by_page = list_reach_by_page([PageModule8], call_graph)
      sync_constants = build_sync_constants(reach_by_page, module_info_plt, false)

      refute MapSet.member?(sync_constants.entity_types, RoleGrant)
    end

    # A check's argument is whatever a template passes - a constructed struct as often as a
    # queried row - so which types get checked is not derivable from the queries, and every
    # policied type's rules ship. What stays out is exactly the types declaring no policy,
    # which is what lets the client read an ABSENT entry as the server's own default deny.
    test "names every policied type when a page checks permissions on the client", %{
      call_graph: call_graph,
      module_info_plt: module_info_plt
    } do
      reach_by_page = list_reach_by_page([PageModule8], call_graph)
      sync_constants = build_sync_constants(reach_by_page, module_info_plt, true)

      assert MapSet.member?(sync_constants.entity_types, PolicyEntity)
      refute MapSet.member?(sync_constants.entity_types, Entity4)
    end

    test "leaves unqueried policied types out when no page checks permissions on the client", %{
      call_graph: call_graph,
      module_info_plt: module_info_plt
    } do
      reach_by_page = list_reach_by_page([PageModule8], call_graph)
      sync_constants = build_sync_constants(reach_by_page, module_info_plt, false)

      refute MapSet.member?(sync_constants.entity_types, PolicyEntity)
    end

    test "records no model hash when the module info PLT records no entity type" do
      assert build_sync_constants([], PLT.start()) == %{
               entity_types: MapSet.new(),
               model_hash: nil,
               permission_checking?: false,
               prop_params: %{}
             }
    end

    # Whatever the pages reach: the hash is of the project's whole data model, the one the running
    # app answers a client's greeting by.
    test "records the hash of the data model the module info PLT records", %{
      sync_constants: sync_constants
    } do
      expected =
        Reflection.list_entities()
        |> Model.from_modules(Reflection.list_roles())
        |> Model.hash()

      assert sync_constants.model_hash == expected
    end
  end

  describe "build_sync_constants_js/1" do
    test "renders the model hash the sync constants carry" do
      assert build_sync_constants_js(@empty_sync_constants) ==
               ~s/globalThis.Hologram.sync = {model: {}, modelHash: "my_model_hash", propParams: {}, protocolVersion: #{Frame.protocol_version()}};/
    end

    # A build declaring no entity type says null, so no client of it asks to sync.
    test "renders null when the sync constants carry no model hash" do
      sync_constants = %{@empty_sync_constants | model_hash: nil}

      assert build_sync_constants_js(sync_constants) == "globalThis.Hologram.sync = null;"
    end
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

  describe "build_chunk_js/5" do
    test "has both Erlang and Elixir function defs", %{ir_plt: ir_plt} do
      mfas = [{Module22, :my_fun, 0}, {:lists, :reverse, 1}]

      result = build_chunk_js(mfas, ir_plt, PLT.start(), MapSet.new(), js_dir: @js_dir)

      assert String.contains?(
               result,
               ~s/Interpreter.defineElixirFunction("Hologram.Test.Fixtures.Compiler.Module22"/
             )

      assert String.contains?(result, ~s/Interpreter.defineErlangFunction("lists", "reverse", 1/)
    end

    test "has no timing code", %{ir_plt: ir_plt} do
      mfas = [{Module22, :my_fun, 0}]

      result = build_chunk_js(mfas, ir_plt, PLT.start(), MapSet.new(), js_dir: @js_dir)

      refute String.contains?(result, "PerformanceTimer")
      refute String.contains?(result, "console.debug")
    end

    test "leaves its function defs for the runtime to define, under its own digest", %{
      ir_plt: ir_plt
    } do
      mfas = [{Module22, :my_fun, 0}]

      result = build_chunk_js(mfas, ir_plt, PLT.start(), MapSet.new(), js_dir: @js_dir)

      js_fragment_1 = "globalThis.Hologram.pendingScripts ??= [];"
      js_fragment_2 = "globalThis.Hologram.pendingScripts.push({"

      js_fragment_3 =
        ~S"digest: new URL(document.currentScript.src).pathname.match(/-([^-]+)\.js$/)[1],"

      js_fragment_4 = "define: (deps) => {"
      js_fragment_5 = ~s/document.dispatchEvent(new CustomEvent("hologram:scriptLoaded"));/

      assert String.contains?(result, js_fragment_1)
      assert String.contains?(result, js_fragment_2)
      assert String.contains?(result, js_fragment_3)
      assert String.contains?(result, js_fragment_4)
      assert String.ends_with?(result, js_fragment_5)
    end

    test "single JS import", %{ir_plt: ir_plt} do
      mfas = [{Module18, :my_fun, 0}]

      result = build_chunk_js(mfas, ir_plt, PLT.start(), MapSet.new(), js_dir: @js_dir)

      js_fixture_path = Path.join([@fixtures_dir, "compiler", "js_fixture_1.mjs"])

      assert length(Regex.scan(~r/import \{/, result)) == 1
      assert String.contains?(result, ~s'import { export_1a as $1 } from "#{js_fixture_path}";')

      assert String.contains?(
               result,
               ~s'Interpreter.registerJsBindings({"Hologram.Test.Fixtures.Compiler.Module18": {"alias_1a": $1}});'
             )
    end

    test "skips the JS imports of the modules the runtime script registers", %{ir_plt: ir_plt} do
      mfas = [{Module18, :my_fun, 0}, {Module22, :my_fun, 0}]

      result =
        build_chunk_js(mfas, ir_plt, PLT.start(), MapSet.new(),
          js_dir: @js_dir,
          runtime_js_binding_modules: MapSet.new([Module18])
        )

      js_fixture_1_path = Path.join([@fixtures_dir, "compiler", "js_fixture_1.mjs"])
      js_fixture_2_path = Path.join([@fixtures_dir, "compiler", "js_fixture_2.mjs"])

      assert length(Regex.scan(~r/import \{/, result)) == 1
      assert String.contains?(result, ~s'import { export_2 as $1 } from "#{js_fixture_2_path}";')

      refute String.contains?(result, js_fixture_1_path)

      assert String.contains?(
               result,
               ~s/Interpreter.defineElixirFunction("Hologram.Test.Fixtures.Compiler.Module18"/
             )
    end
  end

  describe "build_chunk_reach!/4" do
    setup %{module_info_plt: module_info_plt} do
      page = Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module1
      protocol = Hologram.Test.Fixtures.Compiler.CallGraph.Protocol1

      call_graph = CallGraph.start(module_info_plt: module_info_plt)
      ir_plt = build_missing_ir!(PLT.start(), [page, protocol])
      CallGraph.build_for_module(call_graph, ir_plt, page)
      CallGraph.build_for_module(call_graph, ir_plt, protocol)

      # The page's client code calls the protocol, and no code names the struct it is implemented for.
      CallGraph.add_edge(call_graph, {page, :action, 3}, {protocol, :my_fun, 1})

      [
        call_graph: call_graph,
        ir_plt: ir_plt,
        result: build_chunk_reach!(call_graph, ir_plt, [page], [])
      ]
    end

    test "builds the IR and the vertices of an implementation for a struct type no code names",
         %{call_graph: call_graph, ir_plt: ir_plt, result: result} do
      struct_impl =
        Hologram.Test.Fixtures.Compiler.CallGraph.Protocol1.Hologram.Test.Fixtures.Compiler.CallGraph.Struct1

      assert struct_impl in result.built_modules
      assert PLT.member?(ir_plt, struct_impl)
      assert struct_impl in CallGraph.modules(call_graph)
      assert CallGraph.has_vertex?(call_graph, {struct_impl, :my_fun, 1})
    end

    test "builds the IR and the vertices of a struct type no code names, with no implementation",
         %{call_graph: call_graph, ir_plt: ir_plt, result: result} do
      struct = Hologram.Test.Fixtures.Compiler.CallGraph.Module25

      assert struct in result.built_modules
      assert PLT.member?(ir_plt, struct)
      assert struct in CallGraph.modules(call_graph)
      assert CallGraph.has_vertex?(call_graph, {struct, :__struct__, 0})
      assert CallGraph.has_vertex?(call_graph, {struct, :__struct__, 1})
    end

    test "builds the IR of exactly the modules it returns, besides the ones built before", %{
      ir_plt: ir_plt,
      result: result
    } do
      page = Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module1
      protocol = Hologram.Test.Fixtures.Compiler.CallGraph.Protocol1

      ir_modules =
        ir_plt
        |> PLT.keys()
        |> Enum.sort()

      assert ir_modules == Enum.sort([page, protocol | result.built_modules])
    end

    test "returns the client protocols", %{result: result} do
      protocol = Hologram.Test.Fixtures.Compiler.CallGraph.Protocol1

      assert result.client_protocols == MapSet.new([protocol])
    end

    test "returns the entry vertices of a struct type by the type", %{result: result} do
      struct = Hologram.Test.Fixtures.Compiler.CallGraph.Struct1

      struct_impl =
        Hologram.Test.Fixtures.Compiler.CallGraph.Protocol1.Hologram.Test.Fixtures.Compiler.CallGraph.Struct1

      assert result.entries_by_type[struct] == [
               {struct_impl, :__impl__, 1},
               {struct_impl, :my_fun, 1},
               {struct, :__struct__, 0},
               {struct, :__struct__, 1}
             ]
    end
  end

  describe "build_chunk_registry_plt/4" do
    setup do
      # Date's own code, the code Date and DateTime share, and Time's own code.
      bundle_infos_by_signature = %{
        MapSet.new([Date]) => %{bundle_name: "chunk", digest: "AAAAAAAA", entry_name: "59b80f19"},
        MapSet.new([Date, DateTime]) => %{
          bundle_name: "chunk",
          digest: "BBBBBBBB",
          entry_name: "0a1b2c3d"
        },
        MapSet.new([Time]) => %{bundle_name: "chunk", digest: "CCCCCCCC", entry_name: "a6274391"}
      }

      build_dir = Path.join("/", "my_build_dir")

      [
        build_dir: build_dir,
        bundle_infos_by_signature: bundle_infos_by_signature,
        opts: [build_dir: build_dir]
      ]
    end

    test "gives a page that preloads no chunk an empty list", %{
      bundle_infos_by_signature: bundle_infos_by_signature,
      opts: opts
    } do
      {plt, _dump_path} =
        build_chunk_registry_plt(bundle_infos_by_signature, %{MyPage1 => []}, [], opts)

      assert PLT.get(plt, {:page, MyPage1}) == {:ok, []}
    end

    test "lists for a page the chunks its types and the runtime's types need", %{
      bundle_infos_by_signature: bundle_infos_by_signature,
      opts: opts
    } do
      chunk_types_by_page = %{MyPage1 => [DateTime], MyPage2 => [Date, Version]}

      {plt, _dump_path} =
        build_chunk_registry_plt(bundle_infos_by_signature, chunk_types_by_page, [Time], opts)

      assert PLT.get(plt, {:page, MyPage1}) ==
               {:ok,
                [
                  "BBBBBBBB",
                  "CCCCCCCC"
                ]}

      assert PLT.get(plt, {:page, MyPage2}) ==
               {:ok,
                [
                  "AAAAAAAA",
                  "BBBBBBBB",
                  "CCCCCCCC"
                ]}
    end

    test "lists for a type every chunk whose signature holds it", %{
      bundle_infos_by_signature: bundle_infos_by_signature,
      opts: opts
    } do
      {plt, _dump_path} = build_chunk_registry_plt(bundle_infos_by_signature, %{}, [], opts)

      assert PLT.get_all(plt) == %{
               {:type, Date} => [
                 "AAAAAAAA",
                 "BBBBBBBB"
               ],
               {:type, DateTime} => ["BBBBBBBB"],
               {:type, Time} => ["CCCCCCCC"]
             }
    end

    test "returns the path of the dump in the build dir", %{
      build_dir: build_dir,
      bundle_infos_by_signature: bundle_infos_by_signature,
      opts: opts
    } do
      expected_dump_path = Path.join(build_dir, "chunk_registry.plt")

      assert {%PLT{}, ^expected_dump_path} =
               build_chunk_registry_plt(bundle_infos_by_signature, %{}, [], opts)
    end
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

  describe "build_kept_page_reach/3" do
    setup do
      info = fn component? ->
        %{digest: 1, mtime: 1, size: 1, page?: false, component?: component?}
      end

      module_info_plt =
        PLT.start()
        |> PLT.put(Module1, info.(false))
        |> PLT.put(Module2, info.(true))
        |> PLT.put(Module3, info.(true))

      [module_info_plt: module_info_plt]
    end

    test "keeps the modules a page reaches, the struct types it names included, and the components among them, sorted",
         %{module_info_plt: module_info_plt} do
      reach = %{
        mfas: [{Module1, :fun_1, 0}, {Module3, :fun_2, 1}, {Module2, :fun_3, 0}],
        types: [Module4]
      }

      assert build_kept_page_reach([{Module1, reach}], [], module_info_plt) == %{
               Module1 => %{
                 checks_permissions?: false,
                 components: [Module2, Module3],
                 modules: MapSet.new([Module1, Module2, Module3, Module4])
               }
             }
    end

    test "leaves out a reached module the module info PLT does not hold as a component", %{
      module_info_plt: module_info_plt
    } do
      reach = %{mfas: [{Module1, :fun_1, 0}, {Enum, :map, 2}], types: []}

      assert %{Module1 => %{components: []}} =
               build_kept_page_reach([{Module1, reach}], [], module_info_plt)
    end

    test "marks the pages given as checking permissions", %{module_info_plt: module_info_plt} do
      reach = %{mfas: [], types: []}

      assert %{
               Module1 => %{checks_permissions?: true},
               Module11 => %{checks_permissions?: false}
             } =
               build_kept_page_reach(
                 [{Module1, reach}, {Module11, reach}],
                 [Module1],
                 module_info_plt
               )
    end

    test "answers for every page it was given", %{module_info_plt: module_info_plt} do
      reach = %{mfas: [], types: []}

      assert build_kept_page_reach([{Module1, reach}, {Module11, reach}], [], module_info_plt) ==
               %{
                 Module1 => %{checks_permissions?: false, components: [], modules: MapSet.new()},
                 Module11 => %{checks_permissions?: false, components: [], modules: MapSet.new()}
               }
    end
  end

  describe "build_missing_ir!/2" do
    test "builds the IR of modules the PLT doesn't hold" do
      ir_plt = PLT.start()

      build_missing_ir!(ir_plt, [Module1, Module2])

      assert {:ok, %IR.ModuleDefinition{module: %IR.AtomType{value: Module1}}} =
               PLT.get(ir_plt, Module1)

      assert {:ok, %IR.ModuleDefinition{module: %IR.AtomType{value: Module2}}} =
               PLT.get(ir_plt, Module2)
    end

    test "leaves the entries it holds alone" do
      ir_plt = PLT.put(PLT.start(), Module1, :ir_1)

      build_missing_ir!(ir_plt, [Module1, Module2])

      assert PLT.get(ir_plt, Module1) == {:ok, :ir_1}
      assert {:ok, %IR.ModuleDefinition{}} = PLT.get(ir_plt, Module2)
    end

    test "returns the PLT" do
      ir_plt = PLT.start()

      assert build_missing_ir!(ir_plt, [Module1]) == ir_plt
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

      Mix.Project.in_project(:umbrella_fixture, umbrella_dir, [app: nil], fn _module ->
        build_missing_ir!(ir_plt, [module])
      end)

      assert {:ok, %IR.ModuleDefinition{module: %IR.AtomType{value: ^module}}} =
               PLT.get(ir_plt, module)
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
        bundle_name: "page",
        digest: "my-digest-1",
        entry_name: MyPage1
      },
      %{
        bundle_name: "runtime",
        digest: "my-digest-2",
        entry_name: nil
      },
      %{
        bundle_name: "page",
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

  describe "build_reach!/3" do
    setup %{module_info_plt: module_info_plt} do
      page = Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module1
      call_graph = CallGraph.start(module_info_plt: module_info_plt)
      ir_plt = build_missing_ir!(PLT.start(), [page])
      CallGraph.build_for_module(call_graph, ir_plt, page)

      diff = %{added_modules: [page], edited_modules: [], removed_modules: []}

      [
        built_modules: build_reach!(call_graph, ir_plt, diff),
        call_graph: call_graph,
        ir_plt: ir_plt
      ]
    end

    test "builds the IR and the vertices of what the page reaches", %{
      built_modules: built_modules,
      call_graph: call_graph,
      ir_plt: ir_plt
    } do
      layout = Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module2

      assert layout in built_modules
      assert PLT.member?(ir_plt, layout)
      assert layout in CallGraph.modules(call_graph)
      assert CallGraph.has_vertex?(call_graph, {layout, :template, 0})
    end

    test "builds neither the IR nor the vertices of a module nothing reaches", %{
      built_modules: built_modules,
      call_graph: call_graph,
      ir_plt: ir_plt
    } do
      unreached_module = Hologram.Test.Fixtures.Compiler.CallGraph.Module9

      refute unreached_module in built_modules
      refute PLT.member?(ir_plt, unreached_module)
      refute unreached_module in CallGraph.modules(call_graph)
    end

    test "builds the IR of exactly the modules it returns, besides the page", %{
      built_modules: built_modules,
      ir_plt: ir_plt
    } do
      page = Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module1

      ir_modules =
        ir_plt
        |> PLT.keys()
        |> Enum.sort()

      assert ir_modules == Enum.sort([page | built_modules])
    end

    test "builds nothing on a walk with an empty diff", %{call_graph: call_graph, ir_plt: ir_plt} do
      diff = %{added_modules: [], edited_modules: [], removed_modules: []}

      assert build_reach!(call_graph, ir_plt, diff) == []
    end
  end

  describe "build_runtime_js/7" do
    setup do
      on_exit(fn ->
        Application.delete_env(:hologram, :client_error_overlay)
        Application.delete_env(:hologram, :client_stacktraces)
      end)

      # A PLT per test, so one test's warm cache can never stand in for another's encoding.
      [encode_plt: PLT.start()]
    end

    test "asks no module whether it is a protocol or an implementation, or declares JS imports, when given the module info PLT",
         %{
           encode_plt: encode_plt,
           ir_plt: ir_plt,
           module_info_plt: module_info_plt,
           runtime_mfas: runtime_mfas
         } do
      {without_plt, checks_without_plt} =
        count_module_self_checks(fn ->
          build_runtime_js(
            runtime_mfas,
            ir_plt,
            encode_plt,
            MapSet.new(),
            [],
            @empty_sync_constants_js,
            js_dir: @js_dir
          )
        end)

      {with_plt, checks_with_plt} =
        count_module_self_checks(fn ->
          build_runtime_js(
            runtime_mfas,
            ir_plt,
            encode_plt,
            MapSet.new(),
            [],
            @empty_sync_constants_js,
            js_dir: @js_dir,
            module_info_plt: module_info_plt
          )
        end)

      assert with_plt == without_plt
      assert checks_without_plt > 0
      assert checks_with_plt == 0
    end

    test "renders reachable function defs", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          encode_plt,
          MapSet.new(),
          [],
          @empty_sync_constants_js,
          js_dir: @js_dir
        )

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

      # The implementation for a struct type is not in the runtime, and the dispatcher names it:
      # it is loaded in a chunk.
      refute String.contains?(
               js,
               ~s/Interpreter.defineElixirFunction("String.Chars.Hologram.Test.Fixtures.Compiler.CallGraph.Module12"/
             )

      assert String.contains?(
               js,
               ~s/Type.atom("Elixir.String.Chars.Hologram.Test.Fixtures.Compiler.CallGraph.Module12")/
             )

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
      js_1 =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          encode_plt,
          MapSet.new(),
          [],
          @empty_sync_constants_js,
          js_dir: @js_dir
        )

      assert {:ok, into_js} = PLT.get(encode_plt, {Enum, :into, 2})

      assert String.starts_with?(
               into_js,
               ~s/Interpreter.defineElixirFunction("Enum", "into", 2, "public"/
             )

      js_2 =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          encode_plt,
          MapSet.new(),
          [],
          @empty_sync_constants_js,
          js_dir: @js_dir
        )

      assert js_2 == js_1
    end

    test "a warm encode PLT is used instead of the module IR", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      js_1 =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          encode_plt,
          MapSet.new(),
          [],
          @empty_sync_constants_js,
          js_dir: @js_dir
        )

      # A clone, so the PLT shared by the whole test module keeps its Enum entry.
      ir_plt_without_enum =
        ir_plt
        |> PLT.clone()
        |> PLT.delete(Enum)

      js_2 =
        build_runtime_js(
          runtime_mfas,
          ir_plt_without_enum,
          encode_plt,
          MapSet.new(),
          [],
          @empty_sync_constants_js,
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
          @empty_sync_constants_js,
          js_dir: @js_dir
        )

      expected_js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          @empty_sync_constants_js,
          js_dir: @js_dir
        )

      assert js == expected_js
      assert PLT.get(encode_plt, undefined_mfa) == {:ok, nil}
    end

    test "does not read the module IR again for a function the module does not define", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      mfas = [{Enum, :hologram_undefined_fun, 9} | runtime_mfas]

      js_1 =
        build_runtime_js(mfas, ir_plt, encode_plt, MapSet.new(), [], @empty_sync_constants_js,
          js_dir: @js_dir
        )

      # A clone, so the PLT shared by the whole test module keeps its Enum entry.
      ir_plt_without_enum =
        ir_plt
        |> PLT.clone()
        |> PLT.delete(Enum)

      js_2 =
        build_runtime_js(
          mfas,
          ir_plt_without_enum,
          encode_plt,
          MapSet.new(),
          [],
          @empty_sync_constants_js,
          js_dir: @js_dir
        )

      assert js_2 == js_1
    end

    test "protocol functions are rendered per entry file and not cached", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          encode_plt,
          MapSet.new(),
          [],
          @empty_sync_constants_js,
          js_dir: @js_dir
        )

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
      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          encode_plt,
          MapSet.new(),
          [],
          @empty_sync_constants_js,
          js_dir: @js_dir
        )

      {into_pos, _length} = :binary.match(js, ~s/defineElixirFunction("Enum", "into", 2/)

      {into_protocol_pos, _length} =
        :binary.match(js, ~s/defineElixirFunction("Enum", "into_protocol", 2/)

      assert into_pos < into_protocol_pos
    end

    test "starts the runtime without waiting for a page script", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      result =
        runtime_mfas
        |> build_runtime_js(ir_plt, encode_plt, MapSet.new(), [], @empty_sync_constants_js,
          js_dir: @js_dir
        )
        |> normalize_newlines()

      assert String.contains?(result, "\n\nHologram.run();\n\n")
      refute String.contains?(result, "pageScriptLoaded")
    end

    test "renders the clause heads of manually ported functions", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          encode_plt,
          MapSet.new(),
          [],
          @empty_sync_constants_js,
          js_dir: @js_dir
        )

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

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          encode_plt,
          MapSet.new(),
          [],
          @empty_sync_constants_js,
          js_dir: @js_dir
        )

      assert String.contains?(
               js,
               "globalThis.Hologram.config = {errorOverlay: true, liveReload: true, stacktraces: true};"
             )
    end

    test "injects the client config when the presentation settings are disabled", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      Application.put_env(:hologram, :client_error_overlay, false)
      Application.put_env(:hologram, :client_stacktraces, false)

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          encode_plt,
          MapSet.new(),
          [],
          @empty_sync_constants_js,
          js_dir: @js_dir
        )

      assert String.contains?(
               js,
               "globalThis.Hologram.config = {errorOverlay: false, liveReload: true, stacktraces: false};"
             )
    end

    test "registers the metadata of the modules it defines", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      Application.put_env(:hologram, :client_stacktraces, true)

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          encode_plt,
          MapSet.new(),
          [],
          @empty_sync_constants_js,
          js_dir: @js_dir
        )

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
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          encode_plt,
          MapSet.new(),
          app_versions,
          @empty_sync_constants_js,
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
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          encode_plt,
          MapSet.new(),
          app_versions,
          @empty_sync_constants_js,
          js_dir: @js_dir
        )

      assert String.contains?(js, ~s/ERTS.appVersions = {"my-app": "9.8.7"};/)
    end

    test "injects the model the bundle was built against", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(@empty_sync_constants),
          js_dir: @js_dir
        )

      assert String.contains?(js, ~s/modelHash: "my_model_hash", /)
    end

    # Every admitted attribute type in one entry, since a value's type is not recoverable from
    # the value itself - the client reads a date, an enum and a uuid apart only by what this says.
    test "injects the attribute types the client reads rows by", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      sync_constants = %{@empty_sync_constants | entity_types: MapSet.new([Entity4])}

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(sync_constants),
          js_dir: @js_dir
        )

      assert String.contains?(
               js,
               ~s/model: {"Hologram.Test.Fixtures.Entity.Module4":{"attributes":{"a":"date",/ <>
                 ~s/"b":"datetime","c":"enum","created_at":"datetime","d":"float","id":"uuid",/ <>
                 ~s/"updated_at":"datetime"},"constraints":{},"creatorRoles":[],/ <>
                 ~s/"defaults":{"c":Type.atom("x")},/ <>
                 ~s/"enumValues":{"c":["x","y"]},"frameworkAttributes":[],/ <>
                 ~s/"operations":["create","delete","grant_role","read","read_roles",/ <>
                 ~s/"revoke_role","update"],"policy":{},/ <>
                 ~s/"relationships":{},"roles":[],"serverOnly":[]}}/
             )
    end

    # The client refuses an undeclared role with the server's own sentence, from this list.
    test "names a type's declared roles, sorted", %{ir_plt: ir_plt, runtime_mfas: runtime_mfas} do
      sync_constants = %{@empty_sync_constants | entity_types: MapSet.new([PolicyEntity])}

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(sync_constants),
          js_dir: @js_dir
        )

      assert String.contains?(js, ~s/"roles":["editor","maintainer","owner","viewer"],/)
    end

    # The client refuses an operation nothing declares with the server's own sentence, from this
    # list - the framework's seven and the type's own, whether or not the build checks permissions
    # (a type declaring nothing renders the seven alone, asserted with the whole entry in "injects
    # the attribute types the client reads rows by").
    test "names the operations a type can be asked about, sorted", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      sync_constants = %{@empty_sync_constants | entity_types: MapSet.new([PolicyEntity])}

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(sync_constants),
          js_dir: @js_dir
        )

      assert String.contains?(
               js,
               ~s/"operations":["archive","create","delete","grant_role","publish","read",/ <>
                 ~s/"read_roles","revoke_role","update"],/
             )
    end

    # The client writes a creator's grants itself as it creates the row, so the build names which
    # roles those are - a type declaring none renders an empty list, asserted with the whole entry
    # in "injects the attribute types the client reads rows by".
    test "names the roles a creator takes, sorted", %{ir_plt: ir_plt, runtime_mfas: runtime_mfas} do
      sync_constants = %{@empty_sync_constants | entity_types: MapSet.new([PolicyEntity])}

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(sync_constants),
          js_dir: @js_dir
        )

      assert String.contains?(js, ~s/"creatorRoles":["maintainer","owner"],/)
    end

    # The client judges a written value by these, so the name a violation is reported under is the
    # name the build writes - min_length, not the camelCase of its neighbours.
    test "injects the declared constraints under the option names a violation names", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      sync_constants = %{@empty_sync_constants | entity_types: MapSet.new([Entity10])}

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(sync_constants),
          js_dir: @js_dir
        )

      assert String.contains?(js, ~s/"bio":{"max_length":10,"optional":true},/)
      assert String.contains?(js, ~s/"country_code":{"length":2,"optional":true},/)
      assert String.contains?(js, ~s/"username":{"max_length":8,"min_length":3,"optional":true}/)
    end

    # A bound is the literal the declaration wrote, and rating declares both spellings of the same
    # number on one attribute - a float attribute takes `min: 0` beside `max: 5.0`, which the wire
    # would spell alike and the term encoder keeps apart.
    test "injects a numeric bound as the encoded term its literal builds", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      sync_constants = %{@empty_sync_constants | entity_types: MapSet.new([Entity10])}

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(sync_constants),
          js_dir: @js_dir
        )

      assert String.contains?(
               js,
               ~s/"count":{"max":Type.integer(10n),"min":Type.integer(1n)},/
             )

      assert String.contains?(
               js,
               ~s/"rating":{"max":Type.float(5.0),"min":Type.integer(0n),"optional":true},/
             )
    end

    test "injects a temporal bound as the encoded struct its literal builds", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      sync_constants = %{@empty_sync_constants | entity_types: MapSet.new([Entity10])}

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(sync_constants),
          js_dir: @js_dir
        )

      assert String.contains?(
               js,
               ~s/"released_on":{"max":Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Date")], / <>
                 ~s/[Type.atom("calendar"), Type.atom("Elixir.Calendar.ISO")], / <>
                 ~s/[Type.atom("day"), Type.integer(31n)], [Type.atom("month"), Type.integer(12n)], / <>
                 ~s/[Type.atom("year"), Type.integer(2030n)]]),"optional":true}/
             )
    end

    # A compiled pattern exists only inside the runtime that compiled it, so what travels is what
    # compiles into one - the source and the options it was written with.
    test "injects a declared format as its source and its options", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      sync_constants = %{@empty_sync_constants | entity_types: MapSet.new([Entity10])}

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(sync_constants),
          js_dir: @js_dir
        )

      assert String.contains?(
               js,
               ~s/"handle":{"format":{"opts":Type.list([]),"source":"^[a-z_]+$"},"min_length":3,"optional":true},/
             )
    end

    # Not every compile option is a NAME: ~r/@/s reads back as [:dotall, {:newline, :anycrlf}],
    # and a tuple has none to write - which is why the options travel as the term they are.
    test "injects a declared format's options as the term the declaration held", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      sync_constants = %{@empty_sync_constants | entity_types: MapSet.new([Entity10])}

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(sync_constants),
          js_dir: @js_dir
        )

      assert String.contains?(
               js,
               ~s/"email":{"format":{"opts":Type.list([Type.atom("dotall"), / <>
                 ~s/Type.tuple([Type.atom("newline"), Type.atom("anycrlf")])]),"source":"@"},/ <>
                 ~s/"optional":true},/
             )
    end

    # The step travels with the ends: 0..100//5 admits 5 and refuses 7, so a client told only
    # where the range starts and stops would answer differently from the server.
    test "injects a declared range as its ends and its step", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      sync_constants = %{@empty_sync_constants | entity_types: MapSet.new([Entity10])}

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(sync_constants),
          js_dir: @js_dir
        )

      assert String.contains?(
               js,
               ~s/"percent":{"in":{"first":0,"last":100,"step":5},"optional":true},/
             )

      assert String.contains?(
               js,
               ~s/"priority":{"in":{"first":1,"last":5,"step":1},"optional":true},/
             )
    end

    test "injects the uniqueness a declaration asks for", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      sync_constants = %{@empty_sync_constants | entity_types: MapSet.new([Entity19])}

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(sync_constants),
          js_dir: @js_dir
        )

      assert String.contains?(
               js,
               ~s/"constraints":{"code":{"optional":true,"unique":true},"slug":{"unique":true}}/
             )
    end

    # A default is the literal the declaration wrote, so it travels as the term that literal
    # becomes in transpiled code rather than as the way the wire spells the same value - a struct
    # built on the client holds what was declared, and `default: 5` and `default: 5.0` are two
    # different things to hold.
    test "injects the declared defaults as encoded terms", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      sync_constants = %{@empty_sync_constants | entity_types: MapSet.new([Entity4])}

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(sync_constants),
          js_dir: @js_dir
        )

      assert String.contains?(js, ~s/"defaults":{"c":Type.atom("x")}/)
    end

    # A construction naming two of them reports the FIRST, so the order is the refusal's rather
    # than sorted - a client reporting the other would answer a question the server never got.
    test "injects the framework-owned attribute names of a job type, in the order they are refused",
         %{ir_plt: ir_plt, runtime_mfas: runtime_mfas} do
      sync_constants = %{@empty_sync_constants | entity_types: MapSet.new([JobModule1])}

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(sync_constants),
          js_dir: @js_dir
        )

      assert String.contains?(js, ~s/"frameworkAttributes":["actor_id","error","status"]/)
    end

    test "injects the relationships with their target types, cardinality and optionality", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      sync_constants = %{@empty_sync_constants | entity_types: MapSet.new([Entity3])}

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(sync_constants),
          js_dir: @js_dir
        )

      assert String.contains?(
               js,
               ~s/"relationships":{"a":{"optional":false,"toMany":true,"type":"Hologram.Test.Fixtures.Entity.Module2"},/ <>
                 ~s/"b":{"optional":true,"toMany":false,"type":"Hologram.Test.Fixtures.Entity.Module2"},/ <>
                 ~s/"c":{"optional":false,"toMany":false,"type":"Hologram.Test.Fixtures.Entity.Module1"}}/
             )
    end

    # The NAME travels while the value never does: a client that knows the attribute exists and
    # is not for it can say so, where one that never heard of it would answer nil.
    test "injects the names of the attributes a client may not have", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      sync_constants = %{@empty_sync_constants | entity_types: MapSet.new([Entity15])}

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(sync_constants),
          js_dir: @js_dir
        )

      assert String.contains?(js, ~s/"serverOnly":["secret_note","token"]/)
    end

    # A bundle carries the model of the types its own queries reach and no others: a type a
    # client can never hold is one it is told nothing about, its attribute names included.
    test "injects nothing about a type the client can never hold", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      sync_constants = %{@empty_sync_constants | entity_types: MapSet.new([Entity4])}

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(sync_constants),
          js_dir: @js_dir
        )

      refute String.contains?(js, "Hologram.Test.Fixtures.Entity.Module15")
      refute String.contains?(js, "secret_note")
    end

    # The rules a client checks permissions by, spelled the way the rows it checks them against
    # are spelled - a predicate value travels as the wire spells it.
    test "injects the rules a client checks permissions by", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      entity_types = MapSet.new([PolicyEntity, RoleGrant])

      sync_constants = %{
        @empty_sync_constants
        | entity_types: entity_types,
          permission_checking?: true
      }

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(sync_constants),
          js_dir: @js_dir
        )

      # A predicate rule, a grant reference on the entity itself and one on its whole type, and a
      # delegating rule - one of each kind the evaluator has to read.
      assert String.contains?(
               js,
               ~s/"read":[{"predicates":[["public","==",true]],"to":null,"via":null}/
             )

      assert String.contains?(
               js,
               ~s/"to":[["own",["viewer"]],["type","Hologram.Test.Fixtures.Policy.Module2",["admin"]]]/
             )

      assert String.contains?(js, ~s/"publish":[{"predicates":[],"to":null,"via":"parent"}]/)
    end

    # A member and its trailing comma, never a member plus whichever key follows it.
    test "bakes a grant lifecycle rule under its per-role key beside the bare one", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      entity_types = MapSet.new([PolicyEntity, RoleGrant])

      sync_constants = %{
        @empty_sync_constants
        | entity_types: entity_types,
          permission_checking?: true
      }

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(sync_constants),
          js_dir: @js_dir
        )

      owner_rule = ~s/{"predicates":[],"to":[["own",["owner"]]],"via":null}/

      assert String.contains?(js, ~s/"grant_role":[#{owner_rule},#{owner_rule}],/)
      assert String.contains?(js, ~s/"grant_role:editor":[#{owner_rule}],/)
      assert String.contains?(js, ~s/"grant_role:owner":[#{owner_rule}],/)
    end

    # The acting user is named rather than carried: the client binds its own id at evaluation,
    # the way the query kernel binds an actor leaf.
    test "names the acting user in a rule that references them", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      entity_types = MapSet.new([PolicyEntity, RoleGrant])

      sync_constants = %{
        @empty_sync_constants
        | entity_types: entity_types,
          permission_checking?: true
      }

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(sync_constants),
          js_dir: @js_dir
        )

      assert String.contains?(
               js,
               ~s/"archive":[{"predicates":[["author_id","==",{"actor":true}]]/
             )
    end

    # A build whose clients check nothing carries no rules for them to read - and an empty policy
    # grants nothing, which is the answer a client that cannot check should give.
    test "injects an empty policy when no page checks permissions on the client", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      sync_constants = %{@empty_sync_constants | entity_types: MapSet.new([PolicyEntity])}

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(sync_constants),
          js_dir: @js_dir
        )

      assert String.contains?(js, ~s/"policy":{},"relationships":/)
    end

    # The grant type reaches the model by two routes - the check that needs it, and any ordinary
    # query that reads grant rows - so its presence cannot stand in for the check. A build that
    # read it that way would hand every client the whole authorization model because one component
    # listed grants.
    test "injects an empty policy when a query names the grant type and no page checks", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      entity_types = MapSet.new([PolicyEntity, RoleGrant])
      sync_constants = %{@empty_sync_constants | entity_types: entity_types}

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(sync_constants),
          js_dir: @js_dir
        )

      assert String.contains?(js, ~s/"policy":{},"relationships":/)
      refute String.contains?(js, ~s/"predicates":/)
    end

    # The grant type has no server-only attributes and its relationships resolve to the app's
    # designated user entity, so it bakes like any other type once the model names it - by the
    # check that needs it or by a query that reads grant rows, the entry being the same either
    # way. What the CHECK gates is the policy, which is a separate case.
    test "injects the grant type's model entry once the model names it", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      sync_constants = %{@empty_sync_constants | entity_types: MapSet.new([RoleGrant])}

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(sync_constants),
          js_dir: @js_dir
        )

      assert String.contains?(js, ~s/model: {"Hologram.Auth.RoleGrant":{"attributes":{/)

      assert String.contains?(
               js,
               ~s/"user":{"optional":false,"toMany":false,"type":"Hologram.Test.Fixtures.Entity.Module14"}/
             )
    end

    # An attribute declaring no constraint is left out of the map entirely, and a type whose
    # attributes all declare none carries an empty one - the reader fetches the field without
    # asking whether it is there.
    test "injects an empty constraint map for a type declaring no constraint", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      sync_constants = %{@empty_sync_constants | entity_types: MapSet.new([Entity4])}

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(sync_constants),
          js_dir: @js_dir
        )

      assert String.contains?(js, ~s/"constraints":{},/)
    end

    # A type declaring no default carries an empty map rather than nothing at all - the reader
    # fetches the field without asking whether it is there.
    test "injects an empty default map for a type declaring no default", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      sync_constants = %{@empty_sync_constants | entity_types: MapSet.new([Entity15])}

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(sync_constants),
          js_dir: @js_dir
        )

      assert String.contains?(js, ~s/"defaults":{},/)
    end

    # A type holding no enum attribute carries an empty map rather than nothing at all - the
    # reader fetches the field without asking whether it is there.
    test "injects an empty enum-value map for a type with no enum attributes", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      sync_constants = %{@empty_sync_constants | entity_types: MapSet.new([Entity15])}

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(sync_constants),
          js_dir: @js_dir
        )

      assert String.contains?(js, ~s/"enumValues":{},/)
    end

    # Every type carries the list, empty for anything that is not a job - which is what makes it a
    # fact about the type rather than a rule the reader has to know jobs by.
    test "injects an empty framework-attribute list for a type that is not a job", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      sync_constants = %{@empty_sync_constants | entity_types: MapSet.new([Entity15])}

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(sync_constants),
          js_dir: @js_dir
        )

      assert String.contains?(js, ~s/"frameworkAttributes":[],/)
    end

    # A capture travels in the bundle and is called there, but an encoded function carries no
    # argument names - and those names are what each argument binds by.
    test "injects the argument names each query prop binds by", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      prop_params = %{ComponentModule24 => [entities: [:min_b, :max_b]]}
      sync_constants = %{@empty_sync_constants | prop_params: prop_params}

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          build_sync_constants_js(sync_constants),
          js_dir: @js_dir
        )

      # The names are written in argument order, not sorted: they are read positionally, so the
      # order IS the mapping from a prop to the argument it is passed as.
      assert String.contains?(
               js,
               ~s/propParams: {"Hologram.Test.Fixtures.Component.Module24":{"entities":["min_b","max_b"]}}/
             )
    end

    test "injects the wire format the bundle speaks" do
      js =
        build_runtime_js([], PLT.start(), PLT.start(), MapSet.new(), [], @empty_sync_constants_js,
          js_dir: @js_dir
        )

      assert String.contains?(js, ~s/protocolVersion: #{Frame.protocol_version()}};/)
    end

    test "injects no application versions when client stacktraces are disabled", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      Application.put_env(:hologram, :client_stacktraces, false)

      app_versions = [hologram: "0.1.0", my_app: "9.8.7"]

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          encode_plt,
          MapSet.new(),
          app_versions,
          @empty_sync_constants_js,
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

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          encode_plt,
          MapSet.new(),
          [],
          @empty_sync_constants_js,
          js_dir: @js_dir
        )

      assert String.contains?(
               js,
               "globalThis.Hologram.config = {errorOverlay: false, liveReload: true, stacktraces: true};"
             )
    end

    test "turns live reload off in the client config outside the dev and test envs", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      previous_env = System.get_env("HOLOGRAM_ENV")

      on_exit(fn ->
        if previous_env do
          System.put_env("HOLOGRAM_ENV", previous_env)
        else
          System.delete_env("HOLOGRAM_ENV")
        end
      end)

      System.put_env("HOLOGRAM_ENV", "prod")

      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          encode_plt,
          MapSet.new(),
          [],
          @empty_sync_constants_js,
          js_dir: @js_dir
        )

      assert js =~ ~r/globalThis\.Hologram\.config = \{errorOverlay: \w+, liveReload: false, /
    end

    test "no JS imports", %{encode_plt: encode_plt, ir_plt: ir_plt, runtime_mfas: runtime_mfas} do
      mfas = reject_js_import_mfas(runtime_mfas)

      js =
        build_runtime_js(mfas, ir_plt, encode_plt, MapSet.new(), [], @empty_sync_constants_js,
          js_dir: @js_dir
        )

      refute String.contains?(js, "import {")
      refute String.contains?(js, "registerJsBindings")
    end

    test "JS imports of the modules it bundles", %{
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      mfas =
        reject_js_import_mfas(runtime_mfas) ++ [{Module18, :my_fun, 0}, {Module22, :my_fun, 0}]

      js =
        build_runtime_js(mfas, ir_plt, encode_plt, MapSet.new(), [], @empty_sync_constants_js,
          js_dir: @js_dir
        )

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

  describe "bundle/2" do
    test "bundles each entry file" do
      node_modules_path = Path.join([@root_dir, "assets", "node_modules"])
      tmp_dir = Path.join([Reflection.tmp_dir(), "tests", "compiler", "bundle_2"])

      opts = [
        esbuild_bin_path: esbuild_bin_path(node_modules_path),
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
        {nil, entry_file_path_2, "runtime"}
      ]

      assert [
               %{
                 bundle_name: "page",
                 digest: digest_1,
                 entry_name: MyPage,
                 static_bundle_path: static_bundle_path_1,
                 static_source_map_path: static_source_map_path_1
               },
               %{
                 bundle_name: "runtime",
                 digest: digest_2,
                 entry_name: nil,
                 static_bundle_path: static_bundle_path_2,
                 static_source_map_path: static_source_map_path_2
               }
             ] = bundle(entry_files_info, opts)

      assert digest_1 =~ ~r/^[A-Z2-7]{8}$/
      assert digest_2 =~ ~r/^[A-Z2-7]{8}$/

      assert static_bundle_path_1 == Path.join(opts[:static_dir], "page-MyPage-#{digest_1}.js")
      assert static_source_map_path_1 == "#{static_bundle_path_1}.map"
      assert static_bundle_path_2 == Path.join(opts[:static_dir], "runtime-#{digest_2}.js")
      assert static_source_map_path_2 == "#{static_bundle_path_2}.map"

      expected_bundle_js_1 =
        normalize_newlines("""
        (()=>{var o=111;})();
        //# sourceMappingURL=page-MyPage-#{digest_1}.js.map
        """)

      assert File.read!(static_bundle_path_1) == expected_bundle_js_1

      expected_bundle_js_2 =
        normalize_newlines("""
        (()=>{var o=222;})();
        //# sourceMappingURL=runtime-#{digest_2}.js.map
        """)

      assert File.read!(static_bundle_path_2) == expected_bundle_js_2

      expected_source_map_js_1 =
        normalize_newlines("""
        {
          "version": 3,
          "sources": ["../MyPage.entry.js"],
          "sourcesContent": ["export const myVar = 111;\\n"],
          "mappings": "MAAO,IAAMA,EAAQ",
          "names": ["myVar"]
        }
        """)

      assert File.read!(static_source_map_path_1) == expected_source_map_js_1

      expected_source_map_js_2 =
        normalize_newlines("""
        {
          "version": 3,
          "sources": ["../runtime.entry.js"],
          "sourcesContent": ["export const myVar = 222;\\n"],
          "mappings": "MAAO,IAAMA,EAAQ",
          "names": ["myVar"]
        }
        """)

      assert File.read!(static_source_map_path_2) == expected_source_map_js_2
    end

    test "bundles the chunks among the other entries, and returns the bundles in the given order" do
      opts = bundling_opts("bundle_2_chunks_among_others")
      [{chunk_name_1, chunk_path_1}, {chunk_name_2, chunk_path_2}] = create_chunk_entries(2, opts)

      page_path = Path.join(opts[:tmp_dir], "MyPage.entry.js")
      File.write!(page_path, "export const myVar = 111;\n")

      runtime_path = Path.join(opts[:tmp_dir], "runtime.entry.js")
      File.write!(runtime_path, "export const myVar = 222;\n")

      entry_files_info = [
        {chunk_name_1, chunk_path_1, "chunk"},
        {MyPage, page_path, "page"},
        {chunk_name_2, chunk_path_2, "chunk"},
        {nil, runtime_path, "runtime"}
      ]

      {bundles_info, esbuild_runs} = count_esbuild_runs(fn -> bundle(entry_files_info, opts) end)

      assert Enum.map(bundles_info, &{&1.bundle_name, &1.entry_name}) == [
               {"chunk", "00000001"},
               {"page", MyPage},
               {"chunk", "00000002"},
               {"runtime", nil}
             ]

      # One for the page, one for the runtime and one for both chunks.
      assert esbuild_runs == 3
    end

    # With these paths each entry file takes 76 of the command line's 8191 characters, and what the
    # command line holds besides the entry files 311 and the path esbuild is installed at. So 100
    # entry files fit for a path of up to 280 characters, and 150 never do.
    test "bundles the chunks that fit the bound of the command line in one esbuild process" do
      opts = bundling_opts("bundle_2_one_chunk_group")

      entry_files_info =
        100
        |> create_chunk_entries(opts)
        |> Enum.map(fn {entry_name, entry_file_path} ->
          {entry_name, entry_file_path, "chunk"}
        end)

      {bundles_info, esbuild_runs} = count_esbuild_runs(fn -> bundle(entry_files_info, opts) end)

      assert esbuild_runs == 1
      assert Enum.map(bundles_info, & &1.entry_name) == Enum.map(entry_files_info, &elem(&1, 0))
    end

    test "bundles the chunks over the bound of the command line in another esbuild process" do
      opts = bundling_opts("bundle_2_two_chunk_groups")

      entry_files_info =
        150
        |> create_chunk_entries(opts)
        |> Enum.map(fn {entry_name, entry_file_path} ->
          {entry_name, entry_file_path, "chunk"}
        end)

      {bundles_info, esbuild_runs} = count_esbuild_runs(fn -> bundle(entry_files_info, opts) end)

      assert esbuild_runs == 2
      assert Enum.map(bundles_info, & &1.entry_name) == Enum.map(entry_files_info, &elem(&1, 0))

      assert bundles_info
             |> List.last()
             |> Map.fetch!(:static_bundle_path)
             |> File.read!()
             |> String.contains?("150")
    end
  end

  describe "bundle/4" do
    test "valid entry file" do
      node_modules_path = Path.join([@root_dir, "assets", "node_modules"])

      tmp_dir =
        Path.join([Reflection.tmp_dir(), "tests", "compiler", "bundle_4_valid_entry_file"])

      opts = [
        esbuild_bin_path: esbuild_bin_path(node_modules_path),
        node_modules_path: node_modules_path,
        static_dir: Path.join(tmp_dir, "static"),
        tmp_dir: tmp_dir
      ]

      clean_dir(tmp_dir)
      File.mkdir!(opts[:static_dir])

      entry_file_path = Path.join(tmp_dir, "MyPage.entry.js")
      File.write(entry_file_path, "export const myVar = 123;\n")

      assert %{
               bundle_name: "my_bundle_name",
               digest: digest,
               entry_name: MyPage,
               static_bundle_path: static_bundle_path,
               static_source_map_path: static_source_map_path
             } = bundle(MyPage, entry_file_path, "my_bundle_name", opts)

      assert digest =~ ~r/^[A-Z2-7]{8}$/

      assert static_bundle_path ==
               Path.join(opts[:static_dir], "my_bundle_name-MyPage-#{digest}.js")

      assert static_source_map_path == "#{static_bundle_path}.map"

      expected_bundle_js =
        normalize_newlines("""
        (()=>{var o=123;})();
        //# sourceMappingURL=my_bundle_name-MyPage-#{digest}.js.map
        """)

      assert File.read!(static_bundle_path) == expected_bundle_js

      expected_source_map_js =
        normalize_newlines("""
        {
          "version": 3,
          "sources": ["../MyPage.entry.js"],
          "sourcesContent": ["export const myVar = 123;\\n"],
          "mappings": "MAAO,IAAMA,EAAQ",
          "names": ["myVar"]
        }
        """)

      assert File.read!(static_source_map_path) == expected_source_map_js
    end

    test "no entry name" do
      node_modules_path = Path.join([@root_dir, "assets", "node_modules"])

      tmp_dir =
        Path.join([Reflection.tmp_dir(), "tests", "compiler", "bundle_4_no_entry_name"])

      opts = [
        esbuild_bin_path: esbuild_bin_path(node_modules_path),
        node_modules_path: node_modules_path,
        static_dir: Path.join(tmp_dir, "static"),
        tmp_dir: tmp_dir
      ]

      clean_dir(tmp_dir)
      File.mkdir!(opts[:static_dir])

      entry_file_path = Path.join(tmp_dir, "runtime.entry.js")
      File.write(entry_file_path, "export const myVar = 123;\n")

      assert %{digest: digest, entry_name: nil, static_bundle_path: static_bundle_path} =
               bundle(nil, entry_file_path, "my_bundle_name", opts)

      assert digest =~ ~r/^[A-Z2-7]{8}$/
      assert static_bundle_path == Path.join(opts[:static_dir], "my_bundle_name-#{digest}.js")

      assert File.read!(static_bundle_path) =~
               "//# sourceMappingURL=my_bundle_name-#{digest}.js.map"
    end

    test "string entry name" do
      node_modules_path = Path.join([@root_dir, "assets", "node_modules"])

      tmp_dir =
        Path.join([Reflection.tmp_dir(), "tests", "compiler", "bundle_4_string_entry_name"])

      opts = [
        esbuild_bin_path: esbuild_bin_path(node_modules_path),
        node_modules_path: node_modules_path,
        static_dir: Path.join(tmp_dir, "static"),
        tmp_dir: tmp_dir
      ]

      clean_dir(tmp_dir)
      File.mkdir!(opts[:static_dir])

      entry_file_path = Path.join(tmp_dir, "chunk-59b80f19.entry.js")
      File.write(entry_file_path, "export const myVar = 123;\n")

      assert %{
               bundle_name: "chunk",
               digest: digest,
               entry_name: "59b80f19",
               static_bundle_path: static_bundle_path
             } = bundle("59b80f19", entry_file_path, "chunk", opts)

      assert digest =~ ~r/^[A-Z2-7]{8}$/
      # The entry name names the build, not the file.
      assert static_bundle_path == Path.join(opts[:static_dir], "chunk-#{digest}.js")
      assert File.read!(static_bundle_path) =~ "//# sourceMappingURL=chunk-#{digest}.js.map"
    end

    test "string entry names keep the bundles of one bundle name apart" do
      node_modules_path = Path.join([@root_dir, "assets", "node_modules"])

      tmp_dir =
        Path.join([Reflection.tmp_dir(), "tests", "compiler", "bundle_4_string_entry_names"])

      opts = [
        esbuild_bin_path: esbuild_bin_path(node_modules_path),
        node_modules_path: node_modules_path,
        static_dir: Path.join(tmp_dir, "static"),
        tmp_dir: tmp_dir
      ]

      clean_dir(tmp_dir)
      File.mkdir!(opts[:static_dir])

      entry_file_path_1 = Path.join(tmp_dir, "chunk-59b80f19.entry.js")
      File.write(entry_file_path_1, "export const myVar = 123;\n")

      entry_file_path_2 = Path.join(tmp_dir, "chunk-a6274391.entry.js")
      File.write(entry_file_path_2, "export const myVar = 456;\n")

      assert [
               %{digest: digest_1, entry_name: "59b80f19", static_bundle_path: path_1},
               %{digest: digest_2, entry_name: "a6274391", static_bundle_path: path_2}
             ] =
               bundle(
                 [
                   {"59b80f19", entry_file_path_1, "chunk"},
                   {"a6274391", entry_file_path_2, "chunk"}
                 ],
                 opts
               )

      assert digest_1 != digest_2
      assert path_1 == Path.join(opts[:static_dir], "chunk-#{digest_1}.js")
      assert path_2 == Path.join(opts[:static_dir], "chunk-#{digest_2}.js")
      assert File.read!(path_1) =~ "123"
      assert File.read!(path_2) =~ "456"
    end

    test "the same entry file bundles to the same digest" do
      node_modules_path = Path.join([@root_dir, "assets", "node_modules"])

      tmp_dir =
        Path.join([Reflection.tmp_dir(), "tests", "compiler", "bundle_4_same_digest"])

      opts = [
        esbuild_bin_path: esbuild_bin_path(node_modules_path),
        node_modules_path: node_modules_path,
        static_dir: Path.join(tmp_dir, "static"),
        tmp_dir: tmp_dir
      ]

      clean_dir(tmp_dir)
      File.mkdir!(opts[:static_dir])

      entry_file_path = Path.join(tmp_dir, "MyPage.entry.js")
      File.write(entry_file_path, "export const myVar = 123;\n")

      assert %{digest: digest} = bundle(MyPage, entry_file_path, "my_bundle_name", opts)
      assert %{digest: ^digest} = bundle(MyPage, entry_file_path, "my_bundle_name", opts)
    end

    test "a bundle left in the output dir by an earlier run is not picked up" do
      node_modules_path = Path.join([@root_dir, "assets", "node_modules"])

      tmp_dir =
        Path.join([Reflection.tmp_dir(), "tests", "compiler", "bundle_4_stale_output"])

      opts = [
        esbuild_bin_path: esbuild_bin_path(node_modules_path),
        node_modules_path: node_modules_path,
        static_dir: Path.join(tmp_dir, "static"),
        tmp_dir: tmp_dir
      ]

      clean_dir(tmp_dir)
      File.mkdir!(opts[:static_dir])

      entry_file_path = Path.join(tmp_dir, "MyPage.entry.js")
      File.write(entry_file_path, "export const myVar = 123;\n")

      output_dir = Path.join(tmp_dir, "my_bundle_name-MyPage.output")
      File.mkdir_p!(output_dir)
      stale_bundle_path = Path.join(output_dir, "my_bundle_name-MyPage-STALE222.js")
      File.write!(stale_bundle_path, "stale")

      assert %{digest: digest} = bundle(MyPage, entry_file_path, "my_bundle_name", opts)

      assert digest != "STALE222"
      assert File.ls!(output_dir) == []
    end

    test "invalid entry file" do
      node_modules_path = Path.join([@root_dir, "assets", "node_modules"])

      tmp_dir =
        Path.join([Reflection.tmp_dir(), "tests", "compiler", "bundle_4_invalid_entry_file"])

      opts = [
        esbuild_bin_path: esbuild_bin_path(node_modules_path),
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
        esbuild_bin_path: esbuild_bin_path(node_modules_path),
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

    test "does not apply :max_bundle_size to a chunk" do
      node_modules_path = Path.join([@root_dir, "assets", "node_modules"])

      tmp_dir =
        Path.join([Reflection.tmp_dir(), "tests", "compiler", "bundle_4_chunk_max_size"])

      opts = [
        esbuild_bin_path: esbuild_bin_path(node_modules_path),
        node_modules_path: node_modules_path,
        static_dir: Path.join(tmp_dir, "static"),
        tmp_dir: tmp_dir
      ]

      clean_dir(tmp_dir)
      File.mkdir!(opts[:static_dir])

      entry_file_path = Path.join(tmp_dir, "chunk-59b80f19.entry.js")
      File.write!(entry_file_path, "export const myVar = 123;\n")

      Application.put_env(:hologram, :max_bundle_size, 10)

      on_exit(fn ->
        Application.delete_env(:hologram, :max_bundle_size)
      end)

      assert %{static_bundle_path: static_bundle_path} =
               bundle("59b80f19", entry_file_path, "chunk", opts)

      assert File.exists?(static_bundle_path)
    end

    test "records no input for an entry file that imports nothing" do
      test_tmp_dir = Path.join([@tmp_dir, "tests", "compiler", "bundle_4_no_inputs"])
      clean_dir(test_tmp_dir)

      assert bundle_js_inputs("bundle_4_no_inputs", "console.log(1);\n") == %{}
    end

    test "records the file the entry file imports, with a digest of its content" do
      test_tmp_dir = Path.join([@tmp_dir, "tests", "compiler", "bundle_4_direct_input"])
      clean_dir(test_tmp_dir)

      path = write_js_input(test_tmp_dir, "app/helpers.mjs", "export const a = 1;\n")

      js_inputs =
        bundle_js_inputs(
          "bundle_4_direct_input",
          ~s'import { a } from "#{path}";\nconsole.log(a);\n'
        )

      assert js_inputs == %{path => {:digest, :erlang.phash2("export const a = 1;\n")}}
    end

    test "records a file an imported file imports in turn" do
      test_tmp_dir = Path.join([@tmp_dir, "tests", "compiler", "bundle_4_transitive_input"])
      clean_dir(test_tmp_dir)

      helper_path = write_js_input(test_tmp_dir, "app/helpers.mjs", "export const a = 1;\n")

      wrapper_path =
        write_js_input(
          test_tmp_dir,
          "app/wrapper.mjs",
          ~s'import { a } from "./helpers.mjs";\nexport const b = a + 1;\n'
        )

      js_inputs =
        bundle_js_inputs(
          "bundle_4_transitive_input",
          ~s'import { b } from "#{wrapper_path}";\nconsole.log(b);\n'
        )

      recorded_paths =
        js_inputs
        |> Map.keys()
        |> Enum.sort()

      assert recorded_paths == Enum.sort([helper_path, wrapper_path])
      assert {:digest, _digest} = js_inputs[helper_path]
    end

    test "records a package file with its mtime and size" do
      test_tmp_dir = Path.join([@tmp_dir, "tests", "compiler", "bundle_4_package_input"])
      clean_dir(test_tmp_dir)

      path =
        write_js_input(
          test_tmp_dir,
          "app/node_modules/my_package/index.js",
          "export const a = 1;\n"
        )

      %File.Stat{mtime: mtime, size: size} = File.stat!(path, time: :posix)

      js_inputs =
        bundle_js_inputs(
          "bundle_4_package_input",
          ~s'import { a } from "#{path}";\nconsole.log(a);\n'
        )

      assert js_inputs == %{path => {:stat, mtime, size}}
    end

    test "leaves out the files under the js dir" do
      test_tmp_dir = Path.join([@tmp_dir, "tests", "compiler", "bundle_4_js_dir_input"])
      clean_dir(test_tmp_dir)

      path = write_js_input(test_tmp_dir, "hologram_js/hologram.mjs", "export const a = 1;\n")

      js_inputs =
        bundle_js_inputs(
          "bundle_4_js_dir_input",
          ~s'import { a } from "#{path}";\nconsole.log(a);\n'
        )

      assert js_inputs == %{}
    end

    test "records a file written after esbuild started as fresh" do
      test_tmp_dir = Path.join([@tmp_dir, "tests", "compiler", "bundle_4_fresh_input"])
      clean_dir(test_tmp_dir)

      path = write_js_input(test_tmp_dir, "app/helpers.mjs", "export const a = 1;\n")
      File.touch!(path, System.os_time(:second) + 10)

      js_inputs =
        bundle_js_inputs(
          "bundle_4_fresh_input",
          ~s'import { a } from "#{path}";\nconsole.log(a);\n'
        )

      assert js_inputs == %{path => :fresh}
    end
  end

  describe "bundle_chunks/2" do
    test "bundles each entry file into a bundle of its own" do
      opts = bundling_opts("bundle_chunks_2_own_bundles")
      entries = create_chunk_entries(2, opts)

      assert [
               %{
                 bundle_name: "chunk",
                 digest: digest_1,
                 entry_name: "00000001",
                 js_inputs: %{},
                 static_bundle_path: static_bundle_path_1,
                 static_source_map_path: static_source_map_path_1
               },
               %{
                 bundle_name: "chunk",
                 digest: digest_2,
                 entry_name: "00000002",
                 js_inputs: %{},
                 static_bundle_path: static_bundle_path_2,
                 static_source_map_path: static_source_map_path_2
               }
             ] = bundle_chunks(entries, opts)

      assert digest_1 =~ ~r/^[A-Z2-7]{8}$/
      assert digest_2 =~ ~r/^[A-Z2-7]{8}$/
      assert digest_1 != digest_2

      assert static_bundle_path_1 == Path.join(opts[:static_dir], "chunk-#{digest_1}.js")
      assert static_source_map_path_1 == "#{static_bundle_path_1}.map"

      assert static_bundle_path_2 == Path.join(opts[:static_dir], "chunk-#{digest_2}.js")
      assert static_source_map_path_2 == "#{static_bundle_path_2}.map"

      expected_bundle_js_1 =
        normalize_newlines("""
        (()=>{var o=1;})();
        //# sourceMappingURL=chunk-#{digest_1}.js.map
        """)

      assert File.read!(static_bundle_path_1) == expected_bundle_js_1

      expected_bundle_js_2 =
        normalize_newlines("""
        (()=>{var o=2;})();
        //# sourceMappingURL=chunk-#{digest_2}.js.map
        """)

      assert File.read!(static_bundle_path_2) == expected_bundle_js_2

      expected_source_map_js_2 =
        normalize_newlines("""
        {
          "version": 3,
          "sources": ["../chunk-00000002.entry.js"],
          "sourcesContent": ["export const myVar = 2;\\n"],
          "mappings": "MAAO,IAAMA,EAAQ",
          "names": ["myVar"]
        }
        """)

      assert File.read!(static_source_map_path_2) == expected_source_map_js_2
    end

    test "gives an entry file the digest it gets when bundled alone" do
      opts = bundling_opts("bundle_chunks_2_same_digest")
      [{entry_name, entry_file_path} | _rest] = entries = create_chunk_entries(3, opts)

      [%{digest: digest} | _bundles_info] = bundle_chunks(entries, opts)

      assert %{digest: ^digest} = bundle(entry_name, entry_file_path, "chunk", opts)
    end

    test "leaves the output dir empty" do
      opts = bundling_opts("bundle_chunks_2_output_dir")
      entries = create_chunk_entries(2, opts)

      bundle_chunks(entries, opts)

      # Named by the first entry.
      assert opts[:tmp_dir]
             |> Path.join("chunk-00000001.output")
             |> File.ls!() == []
    end

    test "no entry files" do
      opts = bundling_opts("bundle_chunks_2_no_entries")

      {bundles_info, esbuild_runs} = count_esbuild_runs(fn -> bundle_chunks([], opts) end)

      assert bundles_info == []
      assert esbuild_runs == 0
    end

    test "records for each bundle the files its own entry file imports" do
      test_tmp_dir = Path.join([@tmp_dir, "tests", "compiler", "bundle_chunks_2_inputs"])
      clean_dir(test_tmp_dir)

      node_modules_path = Path.join([@root_dir, "assets", "node_modules"])

      opts = [
        esbuild_bin_path: esbuild_bin_path(node_modules_path),
        js_dir: Path.join(test_tmp_dir, "hologram_js"),
        node_modules_path: node_modules_path,
        static_dir: Path.join(test_tmp_dir, "static"),
        tmp_dir: Path.join(test_tmp_dir, "tmp")
      ]

      File.mkdir_p!(opts[:static_dir])
      File.mkdir_p!(opts[:tmp_dir])

      path_1 = write_js_input(test_tmp_dir, "app/helpers_1.mjs", "export const a = 1;\n")
      path_2 = write_js_input(test_tmp_dir, "app/helpers_2.mjs", "export const b = 2;\n")

      entry_file_path_1 = Path.join(opts[:tmp_dir], "chunk-00000001.entry.js")
      File.write!(entry_file_path_1, ~s'import { a } from "#{path_1}";\nconsole.log(a);\n')

      entry_file_path_2 = Path.join(opts[:tmp_dir], "chunk-00000002.entry.js")
      File.write!(entry_file_path_2, ~s'import { b } from "#{path_2}";\nconsole.log(b);\n')

      entry_file_path_3 = Path.join(opts[:tmp_dir], "chunk-00000003.entry.js")
      File.write!(entry_file_path_3, "console.log(3);\n")

      entries = [
        {"00000001", entry_file_path_1},
        {"00000002", entry_file_path_2},
        {"00000003", entry_file_path_3}
      ]

      assert [%{js_inputs: js_inputs_1}, %{js_inputs: js_inputs_2}, %{js_inputs: js_inputs_3}] =
               bundle_chunks(entries, opts)

      assert js_inputs_1 == %{path_1 => {:digest, :erlang.phash2("export const a = 1;\n")}}
      assert js_inputs_2 == %{path_2 => {:digest, :erlang.phash2("export const b = 2;\n")}}
      assert js_inputs_3 == %{}
    end

    test "runs esbuild once" do
      opts = bundling_opts("bundle_chunks_2_one_run")
      entries = create_chunk_entries(3, opts)

      {_bundles_info, esbuild_runs} = count_esbuild_runs(fn -> bundle_chunks(entries, opts) end)

      assert esbuild_runs == 1
    end

    # esbuild names an entry file by its real path, which is not the path it was given.
    @tag :skip_on_windows
    test "tells apart the entry files of a tmp dir reached through a symbolic link" do
      opts = bundling_opts("bundle_chunks_2_symlink")

      real_tmp_dir = Path.join(opts[:tmp_dir], "real")
      linked_tmp_dir = Path.join(opts[:tmp_dir], "linked")
      File.mkdir!(real_tmp_dir)

      real_tmp_dir
      |> Path.expand()
      |> File.ln_s!(linked_tmp_dir)

      linked_opts = Keyword.put(opts, :tmp_dir, linked_tmp_dir)
      entries = create_chunk_entries(2, linked_opts)

      assert [%{static_bundle_path: path_1}, %{static_bundle_path: path_2}] =
               bundle_chunks(entries, linked_opts)

      assert File.read!(path_1) =~ "var o=1;"
      assert File.read!(path_2) =~ "var o=2;"
    end

    test "invalid entry file" do
      opts = bundling_opts("bundle_chunks_2_invalid_entry_file")
      [{_entry_name, entry_file_path} | _rest] = entries = create_chunk_entries(2, opts)
      File.write!(entry_file_path, "export const myVar 123;\n")

      assert_error RuntimeError,
                   "esbuild bundler failed for the chunk entry files (probably there were JavaScript syntax errors)",
                   fn ->
                     bundle_chunks(entries, opts)
                   end

      assert File.ls!(opts[:static_dir]) == []
    end
  end

  describe "chunk_signature_digest/1" do
    test "is the first 8 hex digits of the MD5 of the sorted type names" do
      assert chunk_signature_digest(MapSet.new([Date])) == "59b80f19"
      assert chunk_signature_digest(MapSet.new([Date, Time])) == "59fbfa6b"
    end

    test "is the same whatever order the types were put in" do
      assert chunk_signature_digest(MapSet.new([Time, Date])) ==
               chunk_signature_digest(MapSet.new([Date, Time]))
    end
  end

  describe "client_config/0" do
    setup do
      hologram_env = System.get_env("HOLOGRAM_ENV")

      on_exit(fn ->
        Application.delete_env(:hologram, :client_error_overlay)
        Application.delete_env(:hologram, :client_stacktraces)

        if hologram_env,
          do: System.put_env("HOLOGRAM_ENV", hologram_env),
          else: System.delete_env("HOLOGRAM_ENV")
      end)
    end

    test "names the error overlay, live reload and client stack traces settings" do
      Application.put_env(:hologram, :client_error_overlay, true)
      Application.put_env(:hologram, :client_stacktraces, false)
      System.put_env("HOLOGRAM_ENV", "test")

      assert client_config() == "{errorOverlay: true, liveReload: true, stacktraces: false}"
    end

    test "moves with the error overlay setting" do
      Application.put_env(:hologram, :client_error_overlay, true)
      overlay_on = client_config()

      Application.put_env(:hologram, :client_error_overlay, false)

      assert client_config() != overlay_on
      assert client_config() =~ "errorOverlay: false"
    end

    test "turns live reload off outside dev and test" do
      System.put_env("HOLOGRAM_ENV", "prod")

      assert client_config() =~ "liveReload: false"
    end

    test "is what the runtime bundle sets as the client config", %{
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    } do
      js =
        build_runtime_js(
          runtime_mfas,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          [],
          @empty_sync_constants_js,
          js_dir: @js_dir
        )

      assert String.contains?(js, "globalThis.Hologram.config = #{client_config()};")
    end
  end

  describe "create_chunk_entry_files/5" do
    setup %{module_info_plt: module_info_plt} do
      # Neither signature holds the other, so neither chunk is folded.
      mfas_by_signature = %{
        MapSet.new([Date]) => [{Module18, :my_fun, 0}],
        MapSet.new([Time]) => [{Module22, :my_fun, 0}]
      }

      [
        mfas_by_signature: mfas_by_signature,
        opts: [js_dir: @js_dir, module_info_plt: module_info_plt]
      ]
    end

    test "creates an entry file for each signature, named by its digest", %{
      ir_plt: ir_plt,
      mfas_by_signature: mfas_by_signature,
      opts: opts
    } do
      tmp_dir = Path.join([@tmp_dir, "tests", "compiler", "create_chunk_entry_files_5"])
      clean_dir(tmp_dir)

      result =
        create_chunk_entry_files(
          mfas_by_signature,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          Keyword.put(opts, :tmp_dir, tmp_dir)
        )

      entry_file_path_1 = Path.join(tmp_dir, "chunk-59b80f19.entry.js")
      entry_file_path_2 = Path.join(tmp_dir, "chunk-a6274391.entry.js")

      assert result == [
               {MapSet.new([Date]), "59b80f19", entry_file_path_1},
               {MapSet.new([Time]), "a6274391", entry_file_path_2}
             ]

      entry_file_1 = File.read!(entry_file_path_1)
      entry_file_2 = File.read!(entry_file_path_2)

      js_fragment_1 =
        ~s/Interpreter.defineElixirFunction("Hologram.Test.Fixtures.Compiler.Module18"/

      js_fragment_2 =
        ~s/Interpreter.defineElixirFunction("Hologram.Test.Fixtures.Compiler.Module22"/

      assert String.contains?(entry_file_1, js_fragment_1)
      refute String.contains?(entry_file_1, js_fragment_2)

      assert String.contains?(entry_file_2, js_fragment_2)
      refute String.contains?(entry_file_2, js_fragment_1)
    end

    test "renders a chunk from the encode PLT the folding filled", %{
      ir_plt: ir_plt,
      mfas_by_signature: mfas_by_signature,
      opts: opts
    } do
      tmp_dir = Path.join([@tmp_dir, "tests", "compiler", "create_chunk_entry_files_5_encode"])
      clean_dir(tmp_dir)

      encode_plt = PLT.start()
      chunk_opts = Keyword.put(opts, :tmp_dir, tmp_dir)

      %{chunks: chunks} =
        fold_chunks(mfas_by_signature, ir_plt, encode_plt, MapSet.new(), chunk_opts)

      [{_signature, _signature_digest, entry_file_path} | _rest] =
        create_chunk_entry_files(chunks, ir_plt, encode_plt, MapSet.new(), chunk_opts)

      assert entry_file_path
             |> File.read!()
             |> String.contains?(
               ~s/Interpreter.defineElixirFunction("Hologram.Test.Fixtures.Compiler.Module18"/
             )
    end

    test "skips the JS imports of the modules the runtime script registers", %{
      ir_plt: ir_plt,
      mfas_by_signature: mfas_by_signature,
      opts: opts
    } do
      tmp_dir = Path.join([@tmp_dir, "tests", "compiler", "create_chunk_entry_files_5_imports"])
      clean_dir(tmp_dir)

      chunk_opts =
        opts
        |> Keyword.put(:runtime_js_binding_modules, MapSet.new([Module18]))
        |> Keyword.put(:tmp_dir, tmp_dir)

      [{_signature, _signature_digest, entry_file_path} | _rest] =
        create_chunk_entry_files(mfas_by_signature, ir_plt, PLT.start(), MapSet.new(), chunk_opts)

      js_fixture_1_path = Path.join([@fixtures_dir, "compiler", "js_fixture_1.mjs"])

      refute entry_file_path
             |> File.read!()
             |> String.contains?(js_fixture_1_path)
    end
  end

  describe "create_page_entry_files/6" do
    setup %{
      call_graph: call_graph,
      module_info_plt: module_info_plt,
      runtime_mfas: runtime_mfas
    } do
      page_modules = Reflection.list_pages()

      call_graph_without_runtime_mfas =
        call_graph
        |> CallGraph.clone()
        |> CallGraph.remove_runtime_mfas!(runtime_mfas)

      mfas_by_page = list_mfas_by_page(page_modules, call_graph_without_runtime_mfas)

      [
        mfas_by_page: mfas_by_page,
        opts: [js_dir: @js_dir, module_info_plt: module_info_plt],
        page_modules: page_modules
      ]
    end

    test "creates an entry file for each page", %{
      ir_plt: ir_plt,
      mfas_by_page: mfas_by_page,
      opts: opts,
      page_modules: page_modules
    } do
      tmp_dir = Path.join([@tmp_dir, "tests", "compiler", "create_page_entry_files_6"])
      clean_dir(tmp_dir)

      result =
        create_page_entry_files(
          mfas_by_page,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          MapSet.new(),
          Keyword.put(opts, :tmp_dir, tmp_dir)
        )

      assert Enum.count(result) == Enum.count(page_modules)

      Enum.each(result, fn {page_module, entry_file_path} ->
        assert page_module in page_modules

        module_name = Reflection.module_name(page_module)
        assert entry_file_path == Path.join(tmp_dir, "#{module_name}.entry.js")

        assert entry_file_path
               |> File.read!()
               |> String.contains?("Interpreter.defineElixirFunction")
      end)
    end

    test "reads each module's IR once for all pages", %{
      ir_plt: ir_plt,
      mfas_by_page: mfas_by_page,
      opts: opts
    } do
      tmp_dir = Path.join([@tmp_dir, "tests", "compiler", "create_page_entry_files_6_reads"])
      clean_dir(tmp_dir)

      # The Elixir modules each page reaches, split into protocols, which are read and rendered per
      # page, and the rest, which are read once for all pages.
      modules_by_page =
        Enum.map(mfas_by_page, fn {_page_module, mfas} ->
          mfas
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
          mfas_by_page,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          MapSet.new(),
          Keyword.put(opts, :tmp_dir, tmp_dir)
        )

        assert other_modules != []

        assert :erlang.trace_info({PLT, :get!, 2}, :call_count) ==
                 {:call_count, length(other_modules) + protocol_reads}
      after
        :erlang.trace_pattern({PLT, :get!, 2}, false, [:call_count])
      end
    end

    test "renders the module metadata from the given map", %{
      ir_plt: ir_plt,
      mfas_by_page: mfas_by_page,
      module_info_plt: module_info_plt,
      opts: opts
    } do
      tmp_dir = Path.join([@tmp_dir, "tests", "compiler", "create_page_entry_files_6_metadata"])
      clean_dir(tmp_dir)

      opts = Keyword.put(opts, :tmp_dir, tmp_dir)

      build = fn opts ->
        mfas_by_page
        |> create_page_entry_files(
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

      module_metadata = build_module_metadata(module_info_plt)

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
        count_module_loads.(fn ->
          build.(Keyword.put(opts, :module_metadata, module_metadata))
        end)

      assert with_map == without_map
      {_page_module, first_page_js} = hd(with_map)
      assert String.contains?(first_page_js, "ERTS.registerModuleMetadata(")
      assert loads == baseline_loads
    end
  end

  test "create_runtime_entry_file/7", %{ir_plt: ir_plt, runtime_mfas: runtime_mfas} do
    opts = [
      js_dir: @js_dir,
      tmp_dir: Path.join([@tmp_dir, "tests", "compiler", "create_runtime_entry_file_6"])
    ]

    clean_dir(opts[:tmp_dir])

    entry_file_path =
      create_runtime_entry_file(
        runtime_mfas,
        ir_plt,
        PLT.start(),
        MapSet.new(),
        [],
        @empty_sync_constants_js,
        opts
      )

    assert entry_file_path == Path.join(opts[:tmp_dir], "runtime.entry.js")

    assert entry_file_path
           |> File.read!()
           |> String.contains?("Interpreter.defineElixirFunction")
  end

  describe "delete_module_encodings/2" do
    setup do
      encode_plt =
        PLT.start()
        |> PLT.put({Module1, :fun_1, 0}, "js_1_1")
        |> PLT.put({Module1, :fun_2, 1}, "js_1_2")
        |> PLT.put({Module2, :fun_1, 0}, nil)
        |> PLT.put({Module3, :fun_1, 0}, "js_3_1")

      [encode_plt: encode_plt]
    end

    test "deletes every entry of the given modules", %{encode_plt: encode_plt} do
      delete_module_encodings(encode_plt, [Module1, Module2])

      assert PLT.get(encode_plt, {Module1, :fun_1, 0}) == :error
      assert PLT.get(encode_plt, {Module1, :fun_2, 1}) == :error
      assert PLT.get(encode_plt, {Module2, :fun_1, 0}) == :error
    end

    test "keeps the entries of the other modules", %{encode_plt: encode_plt} do
      delete_module_encodings(encode_plt, [Module1, Module4])

      assert PLT.get(encode_plt, {Module2, :fun_1, 0}) == {:ok, nil}
      assert PLT.get(encode_plt, {Module3, :fun_1, 0}) == {:ok, "js_3_1"}
    end

    test "returns the PLT", %{encode_plt: encode_plt} do
      assert delete_module_encodings(encode_plt, [Module1]) == encode_plt
    end

    test "given no module, reads no key and keeps every entry", %{encode_plt: encode_plt} do
      count = count_calls({PLT, :keys, 1}, fn -> delete_module_encodings(encode_plt, []) end)

      assert count == 0
      assert PLT.size(encode_plt) == 4
    end
  end

  describe "delete_module_ir/2" do
    setup do
      ir_plt =
        PLT.start()
        |> PLT.put(Module1, :ir_1)
        |> PLT.put(Module2, :ir_2)
        |> PLT.put(Module3, :ir_3)

      [ir_plt: ir_plt]
    end

    test "deletes the IR of the given modules and keeps the rest", %{ir_plt: ir_plt} do
      delete_module_ir(ir_plt, [Module1, Module3])

      assert PLT.get(ir_plt, Module1) == :error
      assert PLT.get(ir_plt, Module2) == {:ok, :ir_2}
      assert PLT.get(ir_plt, Module3) == :error
    end

    test "a module with no entry is fine", %{ir_plt: ir_plt} do
      delete_module_ir(ir_plt, [Module4])

      kept_modules =
        ir_plt
        |> PLT.keys()
        |> Enum.sort()

      assert kept_modules == Enum.sort([Module1, Module2, Module3])
    end

    test "returns the PLT", %{ir_plt: ir_plt} do
      assert delete_module_ir(ir_plt, [Module1]) == ir_plt
    end
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

  describe "esbuild_bin_path/1" do
    setup do
      node_modules_path =
        Path.join([@tmp_dir, "tests", "compiler", "esbuild_bin_path_1", "node_modules"])

      clean_dir(node_modules_path)

      [node_modules_path: node_modules_path]
    end

    test "the binary of the one installed Windows platform package", %{
      node_modules_path: node_modules_path
    } do
      binary_path = Path.join([node_modules_path, "@esbuild", "win32-x64", "esbuild.exe"])
      FileUtils.write_p!(binary_path, "")

      assert esbuild_bin_path(node_modules_path) == binary_path
    end

    test "the launcher when no Windows platform package is installed", %{
      node_modules_path: node_modules_path
    } do
      other_binary_path =
        Path.join([node_modules_path, "@esbuild", "darwin-arm64", "bin", "esbuild"])

      FileUtils.write_p!(other_binary_path, "")

      launcher_path = Path.join([node_modules_path, ".bin", "esbuild"])

      assert esbuild_bin_path(node_modules_path) == launcher_path
    end

    test "the launcher when several Windows platform packages are installed", %{
      node_modules_path: node_modules_path
    } do
      ia32_binary_path = Path.join([node_modules_path, "@esbuild", "win32-ia32", "esbuild.exe"])
      FileUtils.write_p!(ia32_binary_path, "")

      x64_binary_path = Path.join([node_modules_path, "@esbuild", "win32-x64", "esbuild.exe"])
      FileUtils.write_p!(x64_binary_path, "")

      launcher_path = Path.join([node_modules_path, ".bin", "esbuild"])

      assert esbuild_bin_path(node_modules_path) == launcher_path
    end
  end

  describe "extract_component_queries/2" do
    setup do
      [entity_types: Reflection.list_entities()]
    end

    test "extracts the queries of every given component, keyed by module", %{
      entity_types: entity_types
    } do
      module_1_term =
        Entity2
        |> filter(a: true)
        |> order_by(:c)
        |> Query.normalize()

      module_11_term =
        Entity2
        |> filter(b: {:>=, %Placeholder{name: :min_b}})
        |> Query.normalize()

      assert extract_component_queries([QueryExtractorModule1, ComponentModule11], entity_types) ==
               %{
                 ComponentModule11 => %{
                   prop_params: [entities: [:min_b]],
                   targets: [ComponentModule11],
                   terms: [module_11_term]
                 },
                 QueryExtractorModule1 => %{
                   prop_params: [],
                   targets: [QueryExtractorModule1],
                   terms: [module_1_term]
                 }
               }
    end

    test "records the module a remote capture points at", %{entity_types: entity_types} do
      assert %{ComponentModule14 => %{targets: [ComponentModule13]}} =
               extract_component_queries([ComponentModule14], entity_types)
    end

    test "records nothing for a component declaring no query prop", %{
      entity_types: entity_types
    } do
      assert extract_component_queries([ComponentModule1], entity_types) == %{
               ComponentModule1 => %{prop_params: [], targets: [], terms: []}
             }
    end

    test "answers for no component with no entry" do
      assert extract_component_queries([], Reflection.list_entities()) == %{}
    end

    # The refusal is the query stage's rather than a validation's - an include sub-term cannot
    # carry the mark at all, so the extraction never reaches a term to object to.
    test "raises for a capture the extractor refuses", %{entity_types: entity_types} do
      expected_msg =
        "include sub-terms take no trust mark - trust/1 goes on the query root and reads the " <>
          "whole query, includes and all, on the server's authority"

      assert_error ArgumentError, expected_msg, fn ->
        extract_component_queries([ComponentModule29], entity_types)
      end
    end
  end

  describe "fingerprint_js_inputs/2" do
    setup do
      test_tmp_dir = Path.join([@tmp_dir, "tests", "compiler", "fingerprint_js_inputs_2"])
      clean_dir(test_tmp_dir)

      app_path = Path.join(test_tmp_dir, "helpers.mjs")
      File.write!(app_path, "export const a = 1;")

      package_path = Path.join([test_tmp_dir, "node_modules", "lodash", "get.js"])

      package_path
      |> Path.dirname()
      |> File.mkdir_p!()

      File.write!(package_path, "module.exports = 2;")

      [app_path: app_path, package_path: package_path, test_tmp_dir: test_tmp_dir]
    end

    test "digests the content of a file outside node_modules", %{app_path: app_path} do
      assert fingerprint_js_inputs([app_path], nil) == %{
               app_path => {:digest, :erlang.phash2("export const a = 1;")}
             }
    end

    test "the digest moves with the content", %{app_path: app_path} do
      %{^app_path => fingerprint} = fingerprint_js_inputs([app_path], nil)
      File.write!(app_path, "export const a = 2;")

      assert fingerprint_js_inputs([app_path], nil)[app_path] != fingerprint
    end

    test "takes the mtime and size of a file under node_modules", %{package_path: package_path} do
      %File.Stat{mtime: mtime, size: size} = File.stat!(package_path, time: :posix)

      assert fingerprint_js_inputs([package_path], nil) == %{package_path => {:stat, mtime, size}}
    end

    test "a file written since the given time is fresh", %{
      app_path: app_path,
      package_path: package_path
    } do
      %File.Stat{mtime: mtime} = File.stat!(app_path, time: :posix)

      assert fingerprint_js_inputs([app_path, package_path], mtime) == %{
               app_path => :fresh,
               package_path => :fresh
             }
    end

    test "a file written before the given time is not fresh", %{app_path: app_path} do
      %File.Stat{mtime: mtime} = File.stat!(app_path, time: :posix)

      assert %{^app_path => {:digest, _digest}} = fingerprint_js_inputs([app_path], mtime + 1)
    end

    test "a file that is not there is missing", %{test_tmp_dir: test_tmp_dir} do
      path = Path.join(test_tmp_dir, "gone.mjs")

      assert fingerprint_js_inputs([path], nil) == %{path => :missing}
    end

    test "a file that cannot be read is missing", %{test_tmp_dir: test_tmp_dir} do
      path = Path.join(test_tmp_dir, "dir.mjs")
      File.mkdir_p!(path)

      assert fingerprint_js_inputs([path], nil) == %{path => :missing}
    end

    test "no paths", _context do
      assert fingerprint_js_inputs([], nil) == %{}
    end
  end

  describe "fold_chunks/5" do
    setup %{module_info_plt: module_info_plt} do
      [opts: [js_dir: @js_dir, module_info_plt: module_info_plt]]
    end

    test "encodes the chunks' functions into the encode PLT", %{ir_plt: ir_plt, opts: opts} do
      mfas_by_signature = %{
        MapSet.new([Date]) => [{Module18, :my_fun, 0}],
        MapSet.new([Time]) => [{Module22, :my_fun, 0}]
      }

      encode_plt = PLT.start()

      fold_chunks(mfas_by_signature, ir_plt, encode_plt, MapSet.new(), opts)

      assert PLT.member?(encode_plt, {Module18, :my_fun, 0})
      assert PLT.member?(encode_plt, {Module22, :my_fun, 0})
    end

    test "folds a chunk under the bound into its superset", %{ir_plt: ir_plt, opts: opts} do
      # Module22.my_fun/0 returns an atom, so the chunk holding it alone is a few hundred bytes of
      # definitions, under what a file of its own costs.
      mfas_by_signature = %{
        MapSet.new([Date]) => [{Module22, :my_fun, 0}],
        MapSet.new([Date, Time]) => [{Module18, :my_fun, 0}]
      }

      result = fold_chunks(mfas_by_signature, ir_plt, PLT.start(), MapSet.new(), opts)

      assert result.chunks == %{
               MapSet.new([Date, Time]) => [{Module18, :my_fun, 0}, {Module22, :my_fun, 0}]
             }
    end

    test "leaves chunks neither of which holds the other apart", %{ir_plt: ir_plt, opts: opts} do
      mfas_by_signature = %{
        MapSet.new([Date]) => [{Module18, :my_fun, 0}],
        MapSet.new([Time]) => [{Module22, :my_fun, 0}]
      }

      result = fold_chunks(mfas_by_signature, ir_plt, PLT.start(), MapSet.new(), opts)

      assert result.chunks == mfas_by_signature
    end

    test "returns the size of each chunk, keyed by its functions", %{ir_plt: ir_plt, opts: opts} do
      mfas_by_signature = %{
        MapSet.new([Date]) => [{Module18, :my_fun, 0}],
        MapSet.new([Time]) => [{Module22, :my_fun, 0}]
      }

      result = fold_chunks(mfas_by_signature, ir_plt, PLT.start(), MapSet.new(), opts)

      assert %{[{Module18, :my_fun, 0}] => size_1, [{Module22, :my_fun, 0}] => size_2} =
               result.sizes

      assert map_size(result.sizes) == 2
      assert size_1 > size_2
      assert size_2 > 0
    end

    test "takes a given size for a chunk with the same functions, and renders no such chunk", %{
      ir_plt: ir_plt,
      opts: opts
    } do
      # Sized alone, the chunk holding Module22.my_fun/0 is under the bound and is folded. The given
      # size keeps it apart, and its function is encoded by nothing.
      mfas_by_signature = %{
        MapSet.new([Date]) => [{Module22, :my_fun, 0}],
        MapSet.new([Date, Time]) => [{Module18, :my_fun, 0}]
      }

      sizes = %{[{Module22, :my_fun, 0}] => 10_000}
      encode_plt = PLT.start()

      result =
        fold_chunks(
          mfas_by_signature,
          ir_plt,
          encode_plt,
          MapSet.new(),
          Keyword.put(opts, :sizes, sizes)
        )

      assert result.chunks == mfas_by_signature
      assert result.sizes[[{Module22, :my_fun, 0}]] == 10_000
      assert PLT.member?(encode_plt, {Module18, :my_fun, 0})
      refute PLT.member?(encode_plt, {Module22, :my_fun, 0})
    end

    test "leaves out a given size of a chunk that is not among the given ones", %{
      ir_plt: ir_plt,
      opts: opts
    } do
      mfas_by_signature = %{MapSet.new([Date]) => [{Module18, :my_fun, 0}]}
      sizes = %{[{Module22, :my_fun, 0}] => 10_000}

      result =
        fold_chunks(
          mfas_by_signature,
          ir_plt,
          PLT.start(),
          MapSet.new(),
          Keyword.put(opts, :sizes, sizes)
        )

      assert Map.keys(result.sizes) == [[{Module18, :my_fun, 0}]]
    end
  end

  describe "fold_small_chunks/2" do
    test "folds a chain of small chunks into the first chunk that is not small" do
      mfas_by_signature = %{
        MapSet.new([Date]) => [{String.Chars.Date, :to_string, 1}],
        MapSet.new([Date, DateTime]) => [{Calendar.ISO, :date_to_string, 3}],
        MapSet.new([Date, DateTime, Time]) => [{Calendar.ISO, :zero_pad, 2}]
      }

      size_by_signature = %{
        MapSet.new([Date]) => 100,
        MapSet.new([Date, DateTime]) => 200,
        MapSet.new([Date, DateTime, Time]) => 4_000
      }

      assert fold_small_chunks(mfas_by_signature, size_by_signature) == %{
               MapSet.new([Date, DateTime, Time]) => [
                 {Calendar.ISO, :date_to_string, 3},
                 {Calendar.ISO, :zero_pad, 2},
                 {String.Chars.Date, :to_string, 1}
               ]
             }
    end

    test "folds a small chunk into its superset, keeping the MFAs sorted" do
      mfas_by_signature = %{
        MapSet.new([Date]) => [{String.Chars.Date, :to_string, 1}],
        MapSet.new([Date, DateTime]) => [{Calendar.ISO, :date_to_string, 3}]
      }

      size_by_signature = %{MapSet.new([Date]) => 300, MapSet.new([Date, DateTime]) => 4_000}

      assert fold_small_chunks(mfas_by_signature, size_by_signature) == %{
               MapSet.new([Date, DateTime]) => [
                 {Calendar.ISO, :date_to_string, 3},
                 {String.Chars.Date, :to_string, 1}
               ]
             }
    end

    test "folds a small chunk into the superset with the fewest types" do
      mfas_by_signature = %{
        MapSet.new([Date]) => [{String.Chars.Date, :to_string, 1}],
        MapSet.new([Date, DateTime]) => [{Calendar.ISO, :date_to_string, 3}],
        MapSet.new([Date, DateTime, Time]) => [{Calendar.ISO, :zero_pad, 2}]
      }

      size_by_signature = %{
        MapSet.new([Date]) => 300,
        MapSet.new([Date, DateTime]) => 4_000,
        MapSet.new([Date, DateTime, Time]) => 4_000
      }

      assert fold_small_chunks(mfas_by_signature, size_by_signature) == %{
               MapSet.new([Date, DateTime]) => [
                 {Calendar.ISO, :date_to_string, 3},
                 {String.Chars.Date, :to_string, 1}
               ],
               MapSet.new([Date, DateTime, Time]) => [{Calendar.ISO, :zero_pad, 2}]
             }
    end

    test "keeps a chunk that grew to the bound by what was folded into it" do
      mfas_by_signature = %{
        MapSet.new([Date]) => [{String.Chars.Date, :to_string, 1}],
        MapSet.new([Date, DateTime]) => [{Calendar.ISO, :date_to_string, 3}],
        MapSet.new([Date, DateTime, Time]) => [{Calendar.ISO, :zero_pad, 2}]
      }

      # 500 + 500 bytes is over the bound of 850.
      size_by_signature = %{
        MapSet.new([Date]) => 500,
        MapSet.new([Date, DateTime]) => 500,
        MapSet.new([Date, DateTime, Time]) => 4_000
      }

      assert fold_small_chunks(mfas_by_signature, size_by_signature) == %{
               MapSet.new([Date, DateTime]) => [
                 {Calendar.ISO, :date_to_string, 3},
                 {String.Chars.Date, :to_string, 1}
               ],
               MapSet.new([Date, DateTime, Time]) => [{Calendar.ISO, :zero_pad, 2}]
             }
    end

    test "keeps a chunk whose size is the bound" do
      mfas_by_signature = %{
        MapSet.new([Date]) => [{String.Chars.Date, :to_string, 1}],
        MapSet.new([Date, DateTime]) => [{Calendar.ISO, :date_to_string, 3}]
      }

      size_by_signature = %{MapSet.new([Date]) => 850, MapSet.new([Date, DateTime]) => 4_000}

      assert fold_small_chunks(mfas_by_signature, size_by_signature) == mfas_by_signature
    end

    test "keeps a small chunk no other chunk's signature holds" do
      mfas_by_signature = %{
        MapSet.new([Date]) => [{String.Chars.Date, :to_string, 1}],
        MapSet.new([Time]) => [{String.Chars.Time, :to_string, 1}]
      }

      size_by_signature = %{MapSet.new([Date]) => 300, MapSet.new([Time]) => 4_000}

      assert fold_small_chunks(mfas_by_signature, size_by_signature) == mfas_by_signature
    end

    test "returns an empty map for no chunks" do
      assert fold_small_chunks(%{}, %{}) == %{}
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

  describe "group_mfas_by_signature/1" do
    test "gives a single type one group holding its MFAs, sorted" do
      mfas_by_type = %{
        Date => [{String.Chars.Date, :to_string, 1}, {Calendar.ISO, :date_to_string, 3}]
      }

      assert group_mfas_by_signature(mfas_by_type) == %{
               MapSet.new([Date]) => [
                 {Calendar.ISO, :date_to_string, 3},
                 {String.Chars.Date, :to_string, 1}
               ]
             }
    end

    test "puts an MFA several types hold in a group of those types alone" do
      mfas_by_type = %{
        Date => [
          {Calendar.ISO, :date_to_string, 3},
          {Calendar.ISO, :zero_pad, 2},
          {String.Chars.Date, :to_string, 1}
        ],
        DateTime => [
          {Calendar.ISO, :date_to_string, 3},
          {Calendar.ISO, :time_to_string, 4},
          {Calendar.ISO, :zero_pad, 2}
        ],
        Time => [
          {Calendar.ISO, :time_to_string, 4},
          {Calendar.ISO, :zero_pad, 2},
          {String.Chars.Time, :to_string, 1}
        ]
      }

      assert group_mfas_by_signature(mfas_by_type) == %{
               MapSet.new([Date]) => [{String.Chars.Date, :to_string, 1}],
               MapSet.new([Date, DateTime]) => [{Calendar.ISO, :date_to_string, 3}],
               MapSet.new([Date, DateTime, Time]) => [{Calendar.ISO, :zero_pad, 2}],
               MapSet.new([DateTime, Time]) => [{Calendar.ISO, :time_to_string, 4}],
               MapSet.new([Time]) => [{String.Chars.Time, :to_string, 1}]
             }
    end

    test "returns an empty map for no types" do
      assert group_mfas_by_signature(%{}) == %{}
    end
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

  describe "js_inputs_changed?/2" do
    test "recorded inputs that match the files now" do
      refute js_inputs_changed?(
               %{"/app/a.mjs" => {:digest, 1}},
               %{"/app/a.mjs" => {:digest, 1}, "/app/b.mjs" => {:digest, 2}}
             )
    end

    test "a recorded input whose fingerprint moved" do
      assert js_inputs_changed?(%{"/app/a.mjs" => {:digest, 1}}, %{"/app/a.mjs" => {:digest, 2}})
    end

    test "a recorded input the fingerprints now do not hold" do
      assert js_inputs_changed?(%{"/app/a.mjs" => {:digest, 1}}, %{})
    end

    test "an input recorded as fresh never matches" do
      assert js_inputs_changed?(%{"/app/a.mjs" => :fresh}, %{"/app/a.mjs" => {:digest, 1}})
    end

    test "no recorded input" do
      refute js_inputs_changed?(%{}, %{})
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
    assert count_calls({PLT, :get_all, 1}, fn -> list_components(plt) end) == 0
  end

  describe "list_ir_modules/2" do
    setup do
      [module_info_plt: small_module_info_plt()]
    end

    test "lists the modules of the MFAs once", %{module_info_plt: module_info_plt} do
      mfas = [
        {Module1, :fun_1, 0},
        {Module1, :fun_2, 0},
        {Module1, :fun_3, 0},
        {Module2, :fun_1, 0},
        {Module2, :fun_2, 1}
      ]

      modules = list_ir_modules(mfas, module_info_plt)

      assert Enum.count(modules, &(&1 == Module1)) == 1
      assert Enum.count(modules, &(&1 == Module2)) == 1
      refute Module3 in modules
    end

    test "lists the modules of the manually ported MFAs", %{module_info_plt: module_info_plt} do
      assert list_ir_modules([], module_info_plt) == [Hologram.JS]
    end

    test "leaves out modules the module info PLT doesn't hold", %{
      module_info_plt: module_info_plt
    } do
      mfas = [{Module1, :fun_1, 0}, {:lists, :map, 2}, {Module4, :fun_1, 0}]

      modules = list_ir_modules(mfas, module_info_plt)

      assert Enum.sort(modules) == Enum.sort([Module1, Hologram.JS])
    end
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

  describe "list_kept_modules/3" do
    setup do
      [module_info_plt: small_module_info_plt()]
    end

    test "lists the modules of the runtime MFAs", %{module_info_plt: module_info_plt} do
      modules = list_kept_modules([{Module1, :fun_1, 0}], [], module_info_plt)

      assert Enum.sort(modules) == Enum.sort([Module1, Hologram.JS])
    end

    test "lists the modules of the manually ported MFAs", %{module_info_plt: module_info_plt} do
      assert list_kept_modules([], [], module_info_plt) == [Hologram.JS]
    end

    test "lists the modules the pages reach", %{module_info_plt: module_info_plt} do
      modules_by_page = [
        {Module11, MapSet.new([Module1, Module2])},
        {Module12, MapSet.new([Module2, Module3])}
      ]

      modules = list_kept_modules([], modules_by_page, module_info_plt)

      assert Enum.sort(modules) == Enum.sort([Hologram.JS, Module1, Module2, Module3])
    end

    test "leaves out modules the module info PLT doesn't hold", %{
      module_info_plt: module_info_plt
    } do
      modules_by_page = [{Module11, MapSet.new([Module1, Module4, :lists])}]

      modules = list_kept_modules([], modules_by_page, module_info_plt)

      assert Enum.sort(modules) == Enum.sort([Hologram.JS, Module1])
    end

    test "lists each module once", %{module_info_plt: module_info_plt} do
      modules_by_page = [{Module11, MapSet.new([Module1])}]

      modules = list_kept_modules([{Module1, :fun_1, 0}], modules_by_page, module_info_plt)

      assert Enum.sort(modules) == Enum.sort([Hologram.JS, Module1])
    end
  end

  describe "list_mfas_by_page/3" do
    setup %{call_graph: call_graph, runtime_mfas: runtime_mfas} do
      call_graph_without_runtime_mfas =
        call_graph
        |> CallGraph.clone()
        |> CallGraph.remove_runtime_mfas!(runtime_mfas)

      [
        call_graph_without_runtime_mfas: call_graph_without_runtime_mfas,
        page_modules: Reflection.list_pages()
      ]
    end

    test "lists each page's reachable MFAs", %{
      call_graph_without_runtime_mfas: call_graph_without_runtime_mfas,
      page_modules: page_modules
    } do
      graph = CallGraph.get_graph(call_graph_without_runtime_mfas)
      module_info_plt = CallGraph.module_info_plt(call_graph_without_runtime_mfas)

      # A PLT per page, so that each expected list is computed on its own.
      expected =
        Enum.map(page_modules, fn page_module ->
          mfas = CallGraph.list_page_mfas(graph, page_module, PLT.start(), module_info_plt)
          {page_module, mfas}
        end)

      result = list_mfas_by_page(page_modules, call_graph_without_runtime_mfas)

      assert length(page_modules) > 1
      assert Enum.all?(result, fn {_page_module, mfas} -> mfas != [] end)
      assert result == expected
    end

    test "passes the opts on to the listing of each page", %{
      call_graph_without_runtime_mfas: call_graph_without_runtime_mfas,
      page_modules: page_modules
    } do
      graph = CallGraph.get_graph(call_graph_without_runtime_mfas)
      module_info_plt = CallGraph.module_info_plt(call_graph_without_runtime_mfas)

      opts = [
        gate: %{
          ir_plt: PLT.start(),
          runtime: %{exposed: %{}, open: MapSet.new(), page_callers: %{}}
        }
      ]

      expected =
        Enum.map(page_modules, fn page_module ->
          mfas = CallGraph.list_page_mfas(graph, page_module, PLT.start(), module_info_plt, opts)
          {page_module, mfas}
        end)

      result = list_mfas_by_page(page_modules, call_graph_without_runtime_mfas, opts)

      assert result == expected

      # A closed gate leaves out the reflection functions a page lists without one.
      assert result != list_mfas_by_page(page_modules, call_graph_without_runtime_mfas)
    end

    test "asks the call graph for its graph once and releases it", %{
      call_graph_without_runtime_mfas: call_graph_without_runtime_mfas,
      page_modules: page_modules
    } do
      %CallGraph{pid: pid} = call_graph_without_runtime_mfas

      count_shared_graphs = fn ->
        Enum.count(:persistent_term.get(), &match?({{CallGraph, _ref}, _graph}, &1))
      end

      shared_graphs_before = count_shared_graphs.()

      # Only the call graph's own process is traced, for the messages it receives.
      :erlang.trace(pid, true, [:receive])

      try do
        list_mfas_by_page(page_modules, call_graph_without_runtime_mfas)
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

    # The analyses PLT is linked to the caller while it runs, so a PLT left running would stay
    # among the caller's links.
    test "stops the analyses PLT it starts", %{
      call_graph_without_runtime_mfas: call_graph_without_runtime_mfas,
      page_modules: page_modules
    } do
      {:links, links_before} = Process.info(self(), :links)

      list_mfas_by_page(page_modules, call_graph_without_runtime_mfas)

      {:links, links_after} = Process.info(self(), :links)

      assert MapSet.new(links_after) == MapSet.new(links_before)
    end

    test "lists nothing and reads no graph for no pages", %{
      call_graph_without_runtime_mfas: call_graph_without_runtime_mfas
    } do
      count =
        count_calls({CallGraph, :with_shared_graph, 2}, fn ->
          assert list_mfas_by_page([], call_graph_without_runtime_mfas) == []
        end)

      assert count == 0
    end
  end

  describe "list_mfas_by_page/5" do
    setup %{call_graph: call_graph, runtime_mfas: runtime_mfas} do
      call_graph_without_runtime_mfas =
        call_graph
        |> CallGraph.clone()
        |> CallGraph.remove_runtime_mfas!(runtime_mfas)

      [
        call_graph_without_runtime_mfas: call_graph_without_runtime_mfas,
        module_info_plt: CallGraph.module_info_plt(call_graph_without_runtime_mfas),
        page_modules: Reflection.list_pages()
      ]
    end

    test "lists each page's reachable MFAs through the graph reader", %{
      call_graph_without_runtime_mfas: call_graph_without_runtime_mfas,
      module_info_plt: module_info_plt,
      page_modules: page_modules
    } do
      result =
        CallGraph.with_shared_graph(call_graph_without_runtime_mfas, fn read_graph ->
          list_mfas_by_page(page_modules, read_graph, PLT.start(), module_info_plt)
        end)

      assert Enum.all?(result, fn {_page_module, mfas} -> mfas != [] end)
      assert result == list_mfas_by_page(page_modules, call_graph_without_runtime_mfas)
    end

    test "keeps the analyses it computes in the given PLT", %{
      call_graph_without_runtime_mfas: call_graph_without_runtime_mfas,
      module_info_plt: module_info_plt,
      page_modules: page_modules
    } do
      analyses = PLT.start()

      CallGraph.with_shared_graph(call_graph_without_runtime_mfas, fn read_graph ->
        list_mfas_by_page(page_modules, read_graph, analyses, module_info_plt)
      end)

      assert Enum.all?(page_modules, &match?({:ok, _analysis}, PLT.get(analyses, &1)))
    end

    test "passes the opts on to the listing of each page", %{
      call_graph_without_runtime_mfas: call_graph_without_runtime_mfas,
      module_info_plt: module_info_plt,
      page_modules: page_modules
    } do
      opts = [
        gate: %{
          ir_plt: PLT.start(),
          runtime: %{exposed: %{}, open: MapSet.new(), page_callers: %{}}
        }
      ]

      result =
        CallGraph.with_shared_graph(call_graph_without_runtime_mfas, fn read_graph ->
          list_mfas_by_page(page_modules, read_graph, PLT.start(), module_info_plt, opts)
        end)

      assert result == list_mfas_by_page(page_modules, call_graph_without_runtime_mfas, opts)
    end

    test "reads the analyses from the PLT", %{
      call_graph_without_runtime_mfas: call_graph_without_runtime_mfas,
      module_info_plt: module_info_plt,
      page_modules: page_modules
    } do
      analyses_items =
        call_graph_without_runtime_mfas
        |> CallGraph.get_graph()
        |> CallGraph.server_callback_analysis_by_templatable(
          page_modules ++ Reflection.list_components(),
          module_info_plt
        )
        |> Map.to_list()

      analyses = PLT.start(items: analyses_items)
      mfa = {CallGraph, :server_callback_analysis_by_templatable, 3}

      count =
        count_calls(mfa, fn ->
          CallGraph.with_shared_graph(call_graph_without_runtime_mfas, fn read_graph ->
            list_mfas_by_page(page_modules, read_graph, analyses, module_info_plt)
          end)
        end)

      assert count == 0
    end
  end

  describe "list_reach_by_page/2" do
    test "lists the MFAs each page reaches and the struct types it names", %{
      call_graph: call_graph
    } do
      [{PageModule13, reach}] = list_reach_by_page([PageModule13], call_graph)

      assert {PageModule13, :action, 3} in reach.mfas
      refute {Entity4, :__struct__, 0} in reach.mfas
      assert Entity4 in reach.types
    end

    test "lists every given page", %{call_graph: call_graph} do
      pages = Reflection.list_pages()

      listed_pages =
        pages
        |> list_reach_by_page(call_graph)
        |> Enum.map(fn {page, _reach} -> page end)

      assert listed_pages == pages
    end

    test "reads no graph for no page" do
      assert list_reach_by_page([], nil) == []
    end
  end

  describe "list_page_links/2" do
    test "a page links to the pages whose modules it reaches" do
      modules_by_page = [{Module1, MapSet.new([Module1, Module2, Module3])}]

      assert list_page_links(modules_by_page, [Module1, Module2, Module3]) == %{
               Module1 => MapSet.new([Module2, Module3]),
               Module2 => MapSet.new(),
               Module3 => MapSet.new()
             }
    end

    test "a page does not link to itself" do
      modules_by_page = [{Module1, MapSet.new([Module1])}]

      assert list_page_links(modules_by_page, [Module1]) == %{Module1 => MapSet.new()}
    end

    test "a reached module that is not a page is not a link" do
      modules_by_page = [{Module1, MapSet.new([Module2])}]

      assert list_page_links(modules_by_page, [Module1]) == %{Module1 => MapSet.new()}
    end

    test "a page with no modules links to no page" do
      assert list_page_links([{Module1, MapSet.new()}], [Module1, Module2]) == %{
               Module1 => MapSet.new(),
               Module2 => MapSet.new()
             }
    end

    test "a page whose modules are not given links to no page" do
      assert list_page_links([], [Module1]) == %{Module1 => MapSet.new()}
    end

    test "every given page gets an entry" do
      modules_by_page = [{Module1, MapSet.new([Module2])}]

      assert list_page_links(modules_by_page, [Module1, Module2]) == %{
               Module1 => MapSet.new([Module2]),
               Module2 => MapSet.new()
             }
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
    assert count_calls({PLT, :get_all, 1}, fn -> list_pages(plt) end) == 0
  end

  describe "list_templatables_to_validate/3" do
    setup do
      [
        empty_diff: %{added_modules: [], edited_modules: [], removed_modules: []},
        template_modules: %{
          page_1: MapSet.new([:component_1]),
          page_2: MapSet.new([:component_2]),
          component_1: MapSet.new(),
          component_2: MapSet.new()
        },
        templatable_modules: [:component_1, :component_2, :page_1, :page_2]
      ]
    end

    test "lists every templatable when no validation is kept", %{
      empty_diff: diff,
      templatable_modules: templatable_modules
    } do
      assert list_templatables_to_validate(templatable_modules, diff, nil) == templatable_modules
    end

    test "lists none with no change", context do
      assert list_templatables_to_validate(
               context.templatable_modules,
               context.empty_diff,
               context.template_modules
             ) == []
    end

    test "lists an edited templatable", context do
      diff = %{context.empty_diff | edited_modules: [:page_2]}

      assert list_templatables_to_validate(
               context.templatable_modules,
               diff,
               context.template_modules
             ) == [:page_2]
    end

    test "lists an added templatable", context do
      templatable_modules = [:page_3 | context.templatable_modules]
      diff = %{context.empty_diff | added_modules: [:page_3]}

      assert list_templatables_to_validate(templatable_modules, diff, context.template_modules) ==
               [:page_3]
    end

    test "lists an edited component and the templatables whose template uses it, not the others",
         context do
      diff = %{context.empty_diff | edited_modules: [:component_1]}

      assert list_templatables_to_validate(
               context.templatable_modules,
               diff,
               context.template_modules
             ) == [:component_1, :page_1]
    end

    test "lists a templatable whose template uses a removed module", context do
      templatable_modules = context.templatable_modules -- [:component_2]
      diff = %{context.empty_diff | removed_modules: [:component_2]}

      assert list_templatables_to_validate(templatable_modules, diff, context.template_modules) ==
               [:page_2]
    end

    # A usage of a module that did not exist when the template was last validated.
    test "lists a templatable whose template uses an added module", context do
      template_modules = %{context.template_modules | page_2: MapSet.new([:component_3])}
      diff = %{context.empty_diff | added_modules: [:component_3]}

      assert list_templatables_to_validate(context.templatable_modules, diff, template_modules) ==
               [:page_2]
    end

    test "lists none when the edited module is used by no template", context do
      diff = %{context.empty_diff | edited_modules: [:plain_module]}

      assert list_templatables_to_validate(
               context.templatable_modules,
               diff,
               context.template_modules
             ) == []
    end
  end

  describe "maybe_install_js_deps/1" do
    setup do
      [assets_dir: assets_dir, build_dir: build_dir] =
        setup_js_deps_test("maybe_install_js_deps_1")

      # The record an install leaves, without one: the deps are the lib's.
      link_lib_js_deps(assets_dir, build_dir)

      [assets_dir: assets_dir, build_dir: build_dir]
    end

    @tag timeout: 300_000
    test "package_json_digest.bin file doesn't exist", %{
      assets_dir: assets_dir,
      build_dir: build_dir
    } do
      package_json_digest_path = Path.join(build_dir, "package_json_digest.bin")
      File.rm!(package_json_digest_path)

      assert maybe_install_js_deps(assets_dir, build_dir) == :ok
      assert File.exists?(package_json_digest_path)
    end

    @tag timeout: 300_000
    test "package-lock.json file doesn't exist", %{assets_dir: assets_dir, build_dir: build_dir} do
      package_lock_json_path = Path.join(assets_dir, "package-lock.json")
      File.rm!(package_lock_json_path)

      assert maybe_install_js_deps(assets_dir, build_dir) == :ok
      assert File.exists?(package_lock_json_path)
    end

    @tag timeout: 300_000
    test "package.json file changed", %{assets_dir: assets_dir, build_dir: build_dir} do
      package_json_digest_path = Path.join(build_dir, "package_json_digest.bin")
      package_json_digest = File.read!(package_json_digest_path)

      package_json_path = Path.join(assets_dir, "package.json")
      File.write!(package_json_path, "{}")

      assert maybe_install_js_deps(assets_dir, build_dir) == :ok
      assert File.read!(package_json_digest_path) != package_json_digest
    end

    test "install is not needed", %{assets_dir: assets_dir, build_dir: build_dir} do
      package_json_digest_path = Path.join(build_dir, "package_json_digest.bin")
      package_json_digest_mtime = File.stat!(package_json_digest_path).mtime

      assert maybe_install_js_deps(assets_dir, build_dir) == nil
      assert File.stat!(package_json_digest_path).mtime == package_json_digest_mtime
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

  describe "module_info_dumped_at/1" do
    setup do
      test_tmp_dir = Path.join([@tmp_dir, "tests", "compiler", "module_info_dumped_at_1"])
      clean_dir(test_tmp_dir)

      [dump_path: Path.join(test_tmp_dir, Reflection.module_info_plt_dump_file_name())]
    end

    test "dump file exists", %{dump_path: dump_path} do
      File.write!(dump_path, "dump")

      assert module_info_dumped_at(dump_path) == File.stat!(dump_path, time: :posix).mtime
    end

    test "dump file doesn't exist", %{dump_path: dump_path} do
      assert module_info_dumped_at(dump_path) == nil
    end
  end

  describe "partition_affected_pages/6" do
    setup do
      test_tmp_dir = Path.join([@tmp_dir, "tests", "compiler", "partition_affected_pages_6"])
      clean_dir(test_tmp_dir)

      bundle_path = Path.join(test_tmp_dir, "page-kept.js")
      File.write!(bundle_path, "bundle")
      File.write!(bundle_path <> ".map", "map")

      page_state = fn modules, path ->
        %{
          bundle_info: %{
            js_inputs: %{},
            static_bundle_path: path,
            static_source_map_path: path <> ".map"
          },
          mfas: Enum.map(modules, &{&1, :fun_1, 0}),
          modules: MapSet.new(modules)
        }
      end

      pages_plt = PLT.start()

      [
        bundle_path: bundle_path,
        page_state: page_state,
        pages_plt: pages_plt,
        static_dir: test_tmp_dir
      ]
    end

    test "a page whose recorded input no longer matches the files is rebuilt", %{
      bundle_path: bundle_path,
      page_state: page_state,
      pages_plt: pages_plt,
      static_dir: static_dir
    } do
      state = page_state.([Module1], bundle_path)
      js_inputs = %{"/app/helpers.mjs" => {:digest, 1}}
      PLT.put(pages_plt, Module1, put_in(state.bundle_info.js_inputs, js_inputs))

      assert partition_affected_pages(
               [Module1],
               MapSet.new(),
               %{"/app/helpers.mjs" => {:digest, 2}},
               MapSet.new(),
               pages_plt,
               static_dir
             ) == {[Module1], []}
    end

    test "a page whose recorded inputs match the files is kept", %{
      bundle_path: bundle_path,
      page_state: page_state,
      pages_plt: pages_plt,
      static_dir: static_dir
    } do
      state = page_state.([Module1], bundle_path)
      js_inputs = %{"/app/helpers.mjs" => {:digest, 1}}
      kept_state = put_in(state.bundle_info.js_inputs, js_inputs)
      PLT.put(pages_plt, Module1, kept_state)

      assert partition_affected_pages(
               [Module1],
               MapSet.new(),
               %{"/app/helpers.mjs" => {:digest, 1}, "/app/other.mjs" => {:digest, 3}},
               MapSet.new(),
               pages_plt,
               static_dir
             ) == {[], [{Module1, kept_state}]}
    end

    test "a page with no kept state is rebuilt", %{pages_plt: pages_plt, static_dir: static_dir} do
      assert partition_affected_pages(
               [Module1],
               MapSet.new(),
               MapSet.new(),
               MapSet.new(),
               pages_plt,
               static_dir
             ) ==
               {[Module1], []}
    end

    test "a page whose kept modules meet the reaching modules is rebuilt", %{
      bundle_path: bundle_path,
      page_state: page_state,
      pages_plt: pages_plt,
      static_dir: static_dir
    } do
      PLT.put(pages_plt, Module1, page_state.([Module1, Module2], bundle_path))

      assert partition_affected_pages(
               [Module1],
               MapSet.new([Module2]),
               MapSet.new(),
               MapSet.new(),
               pages_plt,
               static_dir
             ) ==
               {[Module1], []}
    end

    test "a page whose kept modules do not meet them is kept with its state", %{
      bundle_path: bundle_path,
      page_state: page_state,
      pages_plt: pages_plt,
      static_dir: static_dir
    } do
      state = page_state.([Module1], bundle_path)
      PLT.put(pages_plt, Module1, state)

      assert partition_affected_pages(
               [Module1],
               MapSet.new([Module2]),
               MapSet.new(),
               MapSet.new(),
               pages_plt,
               static_dir
             ) ==
               {[], [{Module1, state}]}
    end

    test "a page whose kept bundle is gone is rebuilt", %{
      page_state: page_state,
      pages_plt: pages_plt,
      static_dir: static_dir
    } do
      PLT.put(pages_plt, Module1, page_state.([Module1], Path.join(static_dir, "page-gone.js")))

      assert partition_affected_pages(
               [Module1],
               MapSet.new(),
               MapSet.new(),
               MapSet.new(),
               pages_plt,
               static_dir
             ) ==
               {[Module1], []}
    end

    test "a page whose kept source map is gone is rebuilt", %{
      bundle_path: bundle_path,
      page_state: page_state,
      pages_plt: pages_plt,
      static_dir: static_dir
    } do
      PLT.put(pages_plt, Module1, page_state.([Module1], bundle_path))
      File.rm!(bundle_path <> ".map")

      assert partition_affected_pages(
               [Module1],
               MapSet.new(),
               MapSet.new(),
               MapSet.new(),
               pages_plt,
               static_dir
             ) ==
               {[Module1], []}
    end

    test "a page whose kept bundle lives in another static dir is rebuilt", %{
      bundle_path: bundle_path,
      page_state: page_state,
      pages_plt: pages_plt
    } do
      PLT.put(pages_plt, Module1, page_state.([Module1], bundle_path))

      assert partition_affected_pages(
               [Module1],
               MapSet.new(),
               MapSet.new(),
               MapSet.new(),
               pages_plt,
               "/other/static"
             ) ==
               {[Module1], []}
    end

    test "keeps the given order in both lists", %{
      bundle_path: bundle_path,
      page_state: page_state,
      pages_plt: pages_plt,
      static_dir: static_dir
    } do
      PLT.put(pages_plt, Module1, page_state.([Module1], bundle_path))
      PLT.put(pages_plt, Module3, page_state.([Module3], bundle_path))

      assert {[Module2, Module4], [{Module1, _state_1}, {Module3, _state_3}]} =
               partition_affected_pages(
                 [Module1, Module2, Module3, Module4],
                 MapSet.new(),
                 MapSet.new(),
                 MapSet.new(),
                 pages_plt,
                 static_dir
               )
    end

    test "a pending page is rebuilt although its kept state is usable", %{
      bundle_path: bundle_path,
      page_state: page_state,
      pages_plt: pages_plt,
      static_dir: static_dir
    } do
      PLT.put(pages_plt, Module1, page_state.([Module1], bundle_path))

      assert partition_affected_pages(
               [Module1],
               MapSet.new(),
               MapSet.new(),
               MapSet.new([Module1]),
               pages_plt,
               static_dir
             ) == {[Module1], []}
    end

    test "a pending page that is not among the given pages is left out", %{
      bundle_path: bundle_path,
      page_state: page_state,
      pages_plt: pages_plt,
      static_dir: static_dir
    } do
      state = page_state.([Module1], bundle_path)
      PLT.put(pages_plt, Module1, state)

      assert partition_affected_pages(
               [Module1],
               MapSet.new(),
               MapSet.new(),
               MapSet.new([Module2]),
               pages_plt,
               static_dir
             ) == {[], [{Module1, state}]}
    end
  end

  describe "partition_pages_to_rebuild/3" do
    setup %{call_graph: call_graph, runtime_mfas: runtime_mfas} do
      call_graph_without_runtime_mfas =
        call_graph
        |> CallGraph.clone()
        |> CallGraph.remove_runtime_mfas!(runtime_mfas)

      page_modules = Reflection.list_pages()

      mfas_by_page = list_mfas_by_page(page_modules, call_graph_without_runtime_mfas)

      test_tmp_dir = Path.join([@tmp_dir, "tests", "compiler", "partition_pages_to_rebuild_3"])
      clean_dir(test_tmp_dir)
      bundle_path = Path.join(test_tmp_dir, "page-kept.js")
      File.write!(bundle_path, "bundle")
      File.write!(bundle_path <> ".map", "map")
      static_dir = test_tmp_dir

      pages_plt = PLT.start()
      page_mfas_plt = PLT.start()

      Enum.each(mfas_by_page, fn {page_module, mfas} ->
        PLT.put(pages_plt, page_module, %{
          bundle_info: %{
            js_inputs: %{},
            static_bundle_path: bundle_path,
            static_source_map_path: bundle_path <> ".map"
          },
          modules: MapSet.new(mfas, &elem(&1, 0))
        })

        PLT.put(page_mfas_plt, page_module, mfas)
      end)

      [
        call_graph_without_runtime_mfas: call_graph_without_runtime_mfas,
        mfas_by_page: mfas_by_page,
        page_mfas_plt: page_mfas_plt,
        page_modules: page_modules,
        pages_plt: pages_plt,
        static_dir: static_dir
      ]
    end

    test "rebuilds a page whose recorded input no longer matches the files", %{
      call_graph_without_runtime_mfas: call_graph_without_runtime_mfas,
      mfas_by_page: mfas_by_page,
      page_modules: page_modules,
      pages_plt: pages_plt,
      static_dir: static_dir
    } do
      [{page_module, _mfas} | _rest] = mfas_by_page
      {:ok, state} = PLT.get(pages_plt, page_module)
      js_inputs = %{"/app/helpers.mjs" => {:digest, 1}}
      PLT.put(pages_plt, page_module, put_in(state.bundle_info.js_inputs, js_inputs))

      {rebuilt, kept} =
        partition_pages_to_rebuild(
          page_modules,
          call_graph_without_runtime_mfas,
          js_fingerprints: %{"/app/helpers.mjs" => {:digest, 2}},
          pages_plt: pages_plt,
          reaching_modules: MapSet.new(),
          static_dir: static_dir
        )

      assert rebuilt == [page_module]
      assert length(kept) == length(page_modules) - 1
    end

    test "names the pages to rebuild and keeps the rest", %{
      call_graph_without_runtime_mfas: call_graph_without_runtime_mfas,
      mfas_by_page: mfas_by_page,
      page_modules: page_modules,
      pages_plt: pages_plt,
      static_dir: static_dir
    } do
      [{reaching_page, _mfas} | _rest] = mfas_by_page

      {rebuilt, kept} =
        partition_pages_to_rebuild(
          page_modules,
          call_graph_without_runtime_mfas,
          pages_plt: pages_plt,
          reaching_modules: MapSet.new([reaching_page]),
          static_dir: static_dir
        )

      assert rebuilt == [reaching_page]
      assert length(kept) == length(page_modules) - 1
      refute reaching_page in Enum.map(kept, &elem(&1, 0))
    end

    test "keeps every page when nothing reaches them", %{
      call_graph_without_runtime_mfas: call_graph_without_runtime_mfas,
      page_modules: page_modules,
      pages_plt: pages_plt,
      static_dir: static_dir
    } do
      assert {[], kept} =
               partition_pages_to_rebuild(
                 page_modules,
                 call_graph_without_runtime_mfas,
                 pages_plt: pages_plt,
                 reaching_modules: MapSet.new(),
                 static_dir: static_dir
               )

      assert length(kept) == length(page_modules)
    end

    test "rebuilds the pending pages although nothing reaches them", %{
      call_graph_without_runtime_mfas: call_graph_without_runtime_mfas,
      mfas_by_page: mfas_by_page,
      page_modules: page_modules,
      pages_plt: pages_plt,
      static_dir: static_dir
    } do
      [{pending_page, _mfas} | _rest] = mfas_by_page

      {rebuilt, kept} =
        partition_pages_to_rebuild(
          page_modules,
          call_graph_without_runtime_mfas,
          pages_plt: pages_plt,
          pending_pages: MapSet.new([pending_page]),
          reaching_modules: MapSet.new(),
          static_dir: static_dir
        )

      assert rebuilt == [pending_page]
      assert length(kept) == length(page_modules) - 1
    end

    test "relisting keeps the pages whose MFAs are unchanged", %{
      call_graph_without_runtime_mfas: call_graph_without_runtime_mfas,
      page_mfas_plt: page_mfas_plt,
      page_modules: page_modules,
      pages_plt: pages_plt,
      static_dir: static_dir
    } do
      assert {[], kept} =
               partition_pages_to_rebuild(
                 page_modules,
                 call_graph_without_runtime_mfas,
                 page_mfas_plt: page_mfas_plt,
                 pages_plt: pages_plt,
                 reaching_modules: MapSet.new(),
                 relist_all?: true,
                 static_dir: static_dir
               )

      assert length(kept) == length(page_modules)
    end

    test "relisting lists the kept pages with the given gate", %{
      call_graph_without_runtime_mfas: call_graph_without_runtime_mfas,
      page_mfas_plt: page_mfas_plt,
      page_modules: page_modules,
      pages_plt: pages_plt,
      static_dir: static_dir
    } do
      gate = %{
        ir_plt: PLT.start(),
        runtime: %{exposed: %{}, open: MapSet.new(), page_callers: %{}}
      }

      # The kept lists are the ones the pages are built from with this gate.
      page_modules
      |> list_mfas_by_page(call_graph_without_runtime_mfas, gate: gate)
      |> Enum.each(fn {page_module, mfas} -> PLT.put(page_mfas_plt, page_module, mfas) end)

      opts = [
        page_mfas_plt: page_mfas_plt,
        pages_plt: pages_plt,
        reaching_modules: MapSet.new(),
        relist_all?: true,
        static_dir: static_dir
      ]

      assert {[], _kept} =
               partition_pages_to_rebuild(
                 page_modules,
                 call_graph_without_runtime_mfas,
                 [{:gate, gate} | opts]
               )

      # Listed without it, the pages whose reflection functions the gate leaves out look moved.
      assert {[_moved_page | _more], _kept} =
               partition_pages_to_rebuild(page_modules, call_graph_without_runtime_mfas, opts)
    end

    test "relisting rebuilds a page with no MFA list", %{
      call_graph_without_runtime_mfas: call_graph_without_runtime_mfas,
      mfas_by_page: mfas_by_page,
      page_mfas_plt: page_mfas_plt,
      page_modules: page_modules,
      pages_plt: pages_plt,
      static_dir: static_dir
    } do
      [{listless_page, _mfas} | _rest] = mfas_by_page

      # A page state loaded from the compile state dump comes without its MFA list.
      PLT.delete(page_mfas_plt, listless_page)

      {rebuilt, kept} =
        partition_pages_to_rebuild(
          page_modules,
          call_graph_without_runtime_mfas,
          page_mfas_plt: page_mfas_plt,
          pages_plt: pages_plt,
          reaching_modules: MapSet.new(),
          relist_all?: true,
          static_dir: static_dir
        )

      assert rebuilt == [listless_page]
      assert length(kept) == length(page_modules) - 1
    end

    test "relisting rebuilds a page whose MFAs moved", %{
      call_graph_without_runtime_mfas: call_graph_without_runtime_mfas,
      mfas_by_page: mfas_by_page,
      page_mfas_plt: page_mfas_plt,
      page_modules: page_modules,
      pages_plt: pages_plt,
      static_dir: static_dir
    } do
      [{moved_page, moved_page_mfas} | _rest] = mfas_by_page

      # The page MFAs PLT decides, not the list in the page state, which is left as the setup put it.
      PLT.put(page_mfas_plt, moved_page, tl(moved_page_mfas))

      {rebuilt, kept} =
        partition_pages_to_rebuild(
          page_modules,
          call_graph_without_runtime_mfas,
          page_mfas_plt: page_mfas_plt,
          pages_plt: pages_plt,
          reaching_modules: MapSet.new(),
          relist_all?: true,
          static_dir: static_dir
        )

      assert rebuilt == [moved_page]
      refute moved_page in Enum.map(kept, &elem(&1, 0))
    end

    test "rebuild_all? rebuilds every page", %{
      call_graph_without_runtime_mfas: call_graph_without_runtime_mfas,
      page_modules: page_modules,
      pages_plt: pages_plt,
      static_dir: static_dir
    } do
      assert {rebuilt, []} =
               partition_pages_to_rebuild(
                 page_modules,
                 call_graph_without_runtime_mfas,
                 pages_plt: pages_plt,
                 reaching_modules: MapSet.new(),
                 rebuild_all?: true,
                 static_dir: static_dir
               )

      assert Enum.sort(rebuilt) == Enum.sort(page_modules)
    end
  end

  describe "patch_module_info_plt!/5" do
    setup do
      [empty_diff: %{added_modules: [], edited_modules: [], removed_modules: []}]
    end

    test "leaves the entry of a module the compiler did not report", %{empty_diff: empty_diff} do
      beam_path = :code.which(Hologram.Reflection)

      # Its mtime moved, so a check of the beam would read it.
      old_info = %{Reflection.beam_info(beam_path) | digest: 1, mtime: 0}
      plt = PLT.put(PLT.start(), Hologram.Reflection, old_info)

      result =
        patch_module_info_plt!(
          plt,
          nil,
          MapSet.new([Hologram.Reflection]),
          [{Hologram.Reflection, beam_path}],
          MapSet.new()
        )

      assert result == {empty_diff, false, %{}}
      assert PLT.get!(plt, Hologram.Reflection) == old_info
    end

    test "reads a compiled module and reports an edit when its digest moved", %{
      empty_diff: empty_diff
    } do
      beam_path = :code.which(Hologram.Reflection)

      old_info = %{Reflection.beam_info(beam_path) | digest: 1}
      plt = PLT.put(PLT.start(), Hologram.Reflection, old_info)

      result =
        patch_module_info_plt!(
          plt,
          nil,
          MapSet.new([Hologram.Reflection]),
          [{Hologram.Reflection, beam_path}],
          MapSet.new([Hologram.Reflection])
        )

      assert result ==
               {%{empty_diff | edited_modules: [Hologram.Reflection]}, true,
                %{Hologram.Reflection => old_info}}

      assert PLT.get!(plt, Hologram.Reflection) == Reflection.beam_info(beam_path)
    end

    test "reports no change for a compiled module whose beam reads as its entry", %{
      empty_diff: empty_diff
    } do
      beam_path = :code.which(Hologram.Reflection)
      plt = PLT.put(PLT.start(), Hologram.Reflection, Reflection.beam_info(beam_path))

      result =
        patch_module_info_plt!(
          plt,
          nil,
          MapSet.new([Hologram.Reflection]),
          [{Hologram.Reflection, beam_path}],
          MapSet.new([Hologram.Reflection])
        )

      assert result == {empty_diff, false, %{}}
    end

    test "reports a change but no edit when only the mtime moved", %{empty_diff: empty_diff} do
      beam_path = :code.which(Hologram.Reflection)

      old_info = %{Reflection.beam_info(beam_path) | mtime: 0}
      plt = PLT.put(PLT.start(), Hologram.Reflection, old_info)

      result =
        patch_module_info_plt!(
          plt,
          nil,
          MapSet.new([Hologram.Reflection]),
          [{Hologram.Reflection, beam_path}],
          MapSet.new([Hologram.Reflection])
        )

      assert result == {empty_diff, true, %{Hologram.Reflection => old_info}}
      assert PLT.get!(plt, Hologram.Reflection) == Reflection.beam_info(beam_path)
    end

    test "adds a beam that has no entry", %{empty_diff: empty_diff} do
      beam_path = :code.which(Hologram.Reflection)
      plt = PLT.start()

      result =
        patch_module_info_plt!(
          plt,
          nil,
          MapSet.new(),
          [{Hologram.Reflection, beam_path}],
          MapSet.new()
        )

      assert result ==
               {%{empty_diff | added_modules: [Hologram.Reflection]}, true,
                %{Hologram.Reflection => nil}}

      assert PLT.get!(plt, Hologram.Reflection) == Reflection.beam_info(beam_path)
    end

    test "removes an editable module whose beam is gone", %{empty_diff: empty_diff} do
      old_info = %{digest: "removed"}
      plt = PLT.put(PLT.start(), :removed_module, old_info)

      result = patch_module_info_plt!(plt, nil, MapSet.new([:removed_module]), [], MapSet.new())

      assert result ==
               {%{empty_diff | removed_modules: [:removed_module]}, true,
                %{removed_module: old_info}}

      assert PLT.get(plt, :removed_module) == :error
    end

    test "checks a module that left the listing while the VM still has its beam", %{
      empty_diff: empty_diff
    } do
      # A consolidated protocol whose directory is off the code path for a moment is listed nowhere,
      # yet the VM loads it from another beam.
      beam_path = :code.which(Hologram.Reflection)

      old_info = %{Reflection.beam_info(beam_path) | digest: 1}
      plt = PLT.put(PLT.start(), Hologram.Reflection, old_info)

      result =
        patch_module_info_plt!(plt, nil, MapSet.new([Hologram.Reflection]), [], MapSet.new())

      assert result ==
               {%{empty_diff | edited_modules: [Hologram.Reflection]}, true,
                %{Hologram.Reflection => old_info}}

      assert PLT.get!(plt, Hologram.Reflection) == Reflection.beam_info(beam_path)
    end

    test "removes a module that left the listing when the path the VM names has no file", %{
      empty_diff: empty_diff
    } do
      module = Hologram.Test.Fixtures.Compiler.PatchModuleInfoPlt.InMemoryModule
      Code.compile_string("defmodule #{inspect(module)} do end")

      on_exit(fn ->
        :code.purge(module)
        :code.delete(module)
      end)

      # A module compiled in memory: the VM names an empty path for it.
      assert :code.which(module) == []

      old_info = %{digest: 1}
      plt = PLT.put(PLT.start(), module, old_info)

      result = patch_module_info_plt!(plt, nil, MapSet.new([module]), [], MapSet.new())

      assert result == {%{empty_diff | removed_modules: [module]}, true, %{module => old_info}}
      assert PLT.get(plt, module) == :error
    end

    test "checks the beam of a protocol the compiler did not report", %{empty_diff: empty_diff} do
      beam_path = :code.which(Enumerable)

      old_info = %{Reflection.beam_info(beam_path) | digest: 1, mtime: 0}
      plt = PLT.put(PLT.start(), Enumerable, old_info)

      result =
        patch_module_info_plt!(
          plt,
          nil,
          MapSet.new([Enumerable]),
          [{Enumerable, beam_path}],
          MapSet.new()
        )

      assert result ==
               {%{empty_diff | edited_modules: [Enumerable]}, true, %{Enumerable => old_info}}

      assert PLT.get!(plt, Enumerable) == Reflection.beam_info(beam_path)
    end

    test "reuses the entry of a protocol whose beam is untouched and older than the dump", %{
      empty_diff: empty_diff
    } do
      beam_path = :code.which(Enumerable)
      %File.Stat{mtime: mtime} = File.stat!(beam_path, time: :posix)
      old_info = %{Reflection.beam_info(beam_path) | digest: 1}
      plt = PLT.put(PLT.start(), Enumerable, old_info)

      result =
        patch_module_info_plt!(
          plt,
          mtime + 1,
          MapSet.new([Enumerable]),
          [{Enumerable, beam_path}],
          MapSet.new()
        )

      assert result == {empty_diff, false, %{}}
      assert PLT.get!(plt, Enumerable) == old_info
    end

    test "leaves every entry as the beams and the reported modules say, and finds the diff" do
      reflection_path = :code.which(Hologram.Reflection)
      compiler_path = :code.which(Hologram.Compiler)
      enumerable_path = :code.which(Enumerable)

      plt_path = :code.which(Hologram.Commons.PLT)
      kept_reflection_info = %{Reflection.beam_info(reflection_path) | digest: 1, mtime: 0}
      old_compiler_info = %{Reflection.beam_info(compiler_path) | digest: 1}
      old_enumerable_info = %{Reflection.beam_info(enumerable_path) | digest: 1, mtime: 0}
      old_removed_info = %{digest: "removed"}

      plt =
        PLT.put(PLT.start(), [
          # Not editable.
          {Enum, %{digest: "kept"}},
          # Editable, not reported, mtime moved: left as it is.
          {Hologram.Reflection, kept_reflection_info},
          # Reported: read again.
          {Hologram.Compiler, old_compiler_info},
          # A protocol not reported, mtime moved: read again.
          {Enumerable, old_enumerable_info},
          # Editable, no beam: removed.
          {:removed_module, old_removed_info}
        ])

      editable_modules =
        MapSet.new([Hologram.Reflection, Hologram.Compiler, Enumerable, :removed_module])

      editable_beams = [
        {Hologram.Reflection, reflection_path},
        {Hologram.Compiler, compiler_path},
        {Enumerable, enumerable_path},
        # No entry: added.
        {Hologram.Commons.PLT, plt_path}
      ]

      compiled_modules = MapSet.new([Hologram.Compiler])

      {diff, changed?, previous_infos} =
        patch_module_info_plt!(plt, nil, editable_modules, editable_beams, compiled_modules)

      assert PLT.get_all(plt) == %{
               Enum => %{digest: "kept"},
               Hologram.Reflection => kept_reflection_info,
               Hologram.Compiler => Reflection.beam_info(compiler_path),
               Enumerable => Reflection.beam_info(enumerable_path),
               Hologram.Commons.PLT => Reflection.beam_info(plt_path)
             }

      assert diff == %{
               added_modules: [Hologram.Commons.PLT],
               edited_modules: [Enumerable, Hologram.Compiler],
               removed_modules: [:removed_module]
             }

      assert changed?

      assert previous_infos == %{
               Hologram.Compiler => old_compiler_info,
               Enumerable => old_enumerable_info,
               Hologram.Commons.PLT => nil,
               removed_module: old_removed_info
             }
    end
  end

  describe "patch_module_metadata/3" do
    setup do
      module_info_plt =
        PLT.put(PLT.start(), [
          {Enum, %{source_path: Reflection.source_path(Enum)}},
          {Hologram.Compiler, %{source_path: Reflection.source_path(Hologram.Compiler)}},
          {Hologram.Reflection, %{source_path: Reflection.source_path(Hologram.Reflection)}}
        ])

      [
        empty_diff: %{added_modules: [], edited_modules: [], removed_modules: []},
        module_info_plt: module_info_plt
      ]
    end

    test "drops the entries of removed and edited modules and builds the entries of added and edited ones",
         %{empty_diff: diff, module_info_plt: module_info_plt} do
      module_metadata = %{
        Aaa.Bbb => %{app: nil, file: "bbb.ex"},
        Enum => %{app: :elixir, file: "lib/enum.ex"},
        Hologram.Reflection => %{app: :stale, file: "stale.ex"}
      }

      diff = %{
        diff
        | added_modules: [Hologram.Compiler],
          edited_modules: [Hologram.Reflection],
          removed_modules: [Aaa.Bbb]
      }

      assert patch_module_metadata(module_metadata, diff, module_info_plt) == %{
               Enum => %{app: :elixir, file: "lib/enum.ex"},
               Hologram.Compiler => %{app: :hologram, file: "lib/hologram/compiler.ex"},
               Hologram.Reflection => %{app: :hologram, file: "lib/hologram/reflection.ex"}
             }
    end

    test "a patched map equals a rebuilt one", %{
      empty_diff: diff,
      module_info_plt: module_info_plt
    } do
      rebuilt_metadata = build_module_metadata(module_info_plt)
      stale_metadata = Map.put(rebuilt_metadata, Hologram.Reflection, %{app: nil, file: "a.ex"})
      diff = %{diff | edited_modules: [Hologram.Reflection]}

      assert patch_module_metadata(stale_metadata, diff, module_info_plt) == rebuilt_metadata
    end

    test "an empty diff changes nothing", %{empty_diff: diff, module_info_plt: module_info_plt} do
      module_metadata = %{Enum => %{app: :stale, file: "stale.ex"}}

      assert patch_module_metadata(module_metadata, diff, module_info_plt) == module_metadata
    end

    test "names the application the full build names", %{empty_diff: diff} do
      # Every 25th module of the loaded applications, with a made-up source path: only the
      # application is compared.
      modules =
        Reflection.list_module_applications()
        |> Map.keys()
        |> Enum.sort()
        |> Enum.take_every(25)

      module_info_plt = PLT.put(PLT.start(), Enum.map(modules, &{&1, %{source_path: "/x/y.ex"}}))
      diff = %{diff | added_modules: modules}

      assert patch_module_metadata(%{}, diff, module_info_plt) ==
               build_module_metadata(module_info_plt)
    end

    test "an added module without a source path gets no entry", %{empty_diff: diff} do
      module_info_plt = PLT.put(PLT.start(), Aaa.Bbb, %{source_path: nil})
      diff = %{diff | added_modules: [Aaa.Bbb]}

      assert patch_module_metadata(%{}, diff, module_info_plt) == %{}
    end
  end

  describe "prune_ir_plt/2" do
    setup do
      ir_plt =
        PLT.start()
        |> PLT.put(Module1, :ir_1)
        |> PLT.put(Module2, :ir_2)
        |> PLT.put(Module3, :ir_3)

      [ir_plt: ir_plt]
    end

    test "deletes the entries of modules not in the list", %{ir_plt: ir_plt} do
      prune_ir_plt(ir_plt, [Module1, Module3])

      assert PLT.get(ir_plt, Module2) == :error
    end

    test "keeps the entries of the listed modules", %{ir_plt: ir_plt} do
      prune_ir_plt(ir_plt, [Module1, Module3, Module4])

      assert PLT.get(ir_plt, Module1) == {:ok, :ir_1}
      assert PLT.get(ir_plt, Module3) == {:ok, :ir_3}
      assert PLT.get(ir_plt, Module4) == :error
    end

    test "returns the modules it deleted", %{ir_plt: ir_plt} do
      dropped_modules = prune_ir_plt(ir_plt, [Module1])

      assert Enum.sort(dropped_modules) == [Module2, Module3]
    end

    test "returns no module when every module is kept", %{ir_plt: ir_plt} do
      assert prune_ir_plt(ir_plt, [Module1, Module2, Module3]) == []
    end
  end

  describe "restore_module_infos/2" do
    test "deletes an entry the update added" do
      plt = PLT.start()
      editable_beams = [{Hologram.Reflection, :code.which(Hologram.Reflection)}]

      {_diff, _changed?, previous_infos} =
        patch_module_info_plt!(plt, nil, MapSet.new(), editable_beams, MapSet.new())

      assert PLT.get_all(plt) != %{}

      assert restore_module_infos(plt, previous_infos) == plt
      assert PLT.get_all(plt) == %{}
    end

    test "puts back an entry the update removed" do
      old_infos = %{removed_module: %{digest: "removed"}}
      plt = PLT.start(items: Map.to_list(old_infos))

      {_diff, _changed?, previous_infos} =
        patch_module_info_plt!(plt, nil, MapSet.new([:removed_module]), [], MapSet.new())

      assert PLT.get_all(plt) != old_infos

      restore_module_infos(plt, previous_infos)

      assert PLT.get_all(plt) == old_infos
    end

    test "puts back an entry the update replaced" do
      beam_path = :code.which(Hologram.Reflection)
      old_infos = %{Hologram.Reflection => %{Reflection.beam_info(beam_path) | digest: 1}}
      plt = PLT.start(items: Map.to_list(old_infos))

      {_diff, _changed?, previous_infos} =
        patch_module_info_plt!(
          plt,
          nil,
          MapSet.new([Hologram.Reflection]),
          [{Hologram.Reflection, beam_path}],
          MapSet.new([Hologram.Reflection])
        )

      assert PLT.get_all(plt) != old_infos

      restore_module_infos(plt, previous_infos)

      assert PLT.get_all(plt) == old_infos
    end
  end

  describe "runtime_changed?/4" do
    setup do
      kept_runtime = %{
        app_versions: [hologram: "1.0.0"],
        bundle_info: %{digest: "a"},
        js_binding_modules: MapSet.new([Module1]),
        mfas: [{Module1, :fun_1, 0}]
      }

      [kept_runtime: kept_runtime]
    end

    test "false when nothing differs", %{kept_runtime: kept_runtime} do
      refute runtime_changed?(
               kept_runtime,
               kept_runtime.mfas,
               kept_runtime.js_binding_modules,
               kept_runtime.app_versions
             )
    end

    test "true when there is no kept runtime", %{kept_runtime: kept_runtime} do
      assert runtime_changed?(
               nil,
               kept_runtime.mfas,
               kept_runtime.js_binding_modules,
               kept_runtime.app_versions
             )
    end

    test "true when the MFAs differ", %{kept_runtime: kept_runtime} do
      assert runtime_changed?(
               kept_runtime,
               [{Module2, :fun_1, 0}],
               kept_runtime.js_binding_modules,
               kept_runtime.app_versions
             )
    end

    test "true when the JS binding modules differ", %{kept_runtime: kept_runtime} do
      assert runtime_changed?(
               kept_runtime,
               kept_runtime.mfas,
               MapSet.new([Module2]),
               kept_runtime.app_versions
             )
    end

    test "true when the app versions differ", %{kept_runtime: kept_runtime} do
      assert runtime_changed?(
               kept_runtime,
               kept_runtime.mfas,
               kept_runtime.js_binding_modules,
               hologram: "1.0.1"
             )
    end
  end

  test "prune_module_def/4" do
    module_def_ir = IR.for_module(Module8)

    module_def_ir_fixture = %{
      module_def_ir
      | body: %IR.Block{
          expressions: [
            %IR.IgnoredExpression{type: :public_macro_definition} | module_def_ir.body.expressions
          ]
        }
    }

    module_mfas = [
      {Module8, :fun_2, 2},
      {Module8, :fun_3, 1}
    ]

    pruned = prune_module_def(module_def_ir_fixture, module_mfas, MapSet.new([Module8]), nil)

    assert pruned == %IR.ModuleDefinition{
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

  test "prune_module_def/4 asks no module when the module info PLT holds them", %{
    module_info_plt: module_info_plt
  } do
    module_mfas = [
      {String.Chars, :impl_for, 1},
      {String.Chars, :struct_impl_for, 1},
      {String.Chars, :to_string, 1}
    ]

    reachable_modules = MapSet.new([String.Chars, String.Chars.Atom, Calendar.ISO])
    module_def_ir = IR.for_module(String.Chars)

    {without_plt, checks_without_plt} =
      count_module_self_checks(fn ->
        prune_module_def(module_def_ir, module_mfas, reachable_modules, nil)
      end)

    {with_plt, checks_with_plt} =
      count_module_self_checks(fn ->
        prune_module_def(module_def_ir, module_mfas, reachable_modules, module_info_plt)
      end)

    assert with_plt == without_plt
    assert checks_without_plt > 0
    assert checks_with_plt == 0
  end

  test "prune_module_def/4 keeps the protocol dispatcher clauses for struct types", %{
    module_info_plt: module_info_plt
  } do
    module_mfas = [
      {String.Chars, :impl_for, 1},
      {String.Chars, :impl_for!, 1},
      {String.Chars, :struct_impl_for, 1},
      {String.Chars, :to_string, 1}
    ]

    # No implementation for a struct type is among the modules.
    reachable_modules = MapSet.new([String.Chars, String.Chars.Atom])

    js =
      String.Chars
      |> IR.for_module()
      |> prune_module_def(module_mfas, reachable_modules, module_info_plt)
      |> Encoder.encode_ir(%Context{module: String.Chars, async_mfas: MapSet.new()})

    assert String.contains?(js, ~s/Type.atom("Elixir.String.Chars.URI")/)
    assert String.contains?(js, ~s/Type.atom("Elixir.String.Chars.Version")/)

    assert String.contains?(
             js,
             ~s/Type.atom("Elixir.String.Chars.Hologram.Test.Fixtures.Compiler.CallGraph.Module12")/
           )
  end

  test "prune_module_def/4 prunes the protocol dispatcher clauses for built-in types to the included implementations",
       %{module_info_plt: module_info_plt} do
    module_mfas = [
      {String.Chars, :impl_for, 1},
      {String.Chars, :impl_for!, 1},
      {String.Chars, :struct_impl_for, 1},
      {String.Chars, :to_string, 1}
    ]

    reachable_modules = MapSet.new([String.Chars, String.Chars.Atom])

    js =
      String.Chars
      |> IR.for_module()
      |> prune_module_def(module_mfas, reachable_modules, module_info_plt)
      |> Encoder.encode_ir(%Context{module: String.Chars, async_mfas: MapSet.new()})

    assert String.contains?(
             js,
             ~s/Interpreter.defineElixirFunction("String.Chars", "impl_for!", 1, "public"/
           )

    assert String.contains?(js, ~s/Type.atom("Elixir.String.Chars.Atom")/)

    refute String.contains?(js, "Elixir.String.Chars.Integer")
    refute String.contains?(js, "Elixir.String.Chars.List")
  end

  describe "validate_operations!/3" do
    # Entity13 declares :publish, :triage and :unlink with roles :editor and :owner; PolicyEntity
    # declares :archive and :publish with :editor, :maintainer, :owner and :viewer - so the build's
    # vocabulary is the framework's seven plus four, and its roles four.
    @declaring_model [Entity13, PolicyEntity]

    defp single_ask_plt(operation) do
      asker_plt("""
      defmodule Hologram.Test.Fixtures.Compiler.OperationAsker do
        def f(user, entity), do: Hologram.Auth.can?(user, #{operation}, entity)
      end
      """)
    end

    test "doesn't raise for a framework operation on a model declaring nothing" do
      graph = asker_graph([{:f, 2, {Hologram.Auth, :can?, 3}}])

      assert validate_operations!([Entity1], graph, single_ask_plt(":read")) == :ok
    end

    # An app with no entity type at all - the umbrella test app's shape - still has the
    # framework's own asks in its call graph, Diff.deltas/4 asking :read among them.
    test "doesn't raise for a framework operation when the build has no entity type" do
      graph = asker_graph([{:f, 2, {Hologram.Auth, :can?, 3}}])

      assert validate_operations!([], graph, single_ask_plt(":read")) == :ok
    end

    test "doesn't raise for an operation some entity type declares" do
      graph = asker_graph([{:f, 2, {Hologram.Auth, :can?, 3}}])

      assert validate_operations!(@declaring_model, graph, single_ask_plt(":triage")) == :ok
    end

    test "doesn't raise for a role tuple naming a role some entity type declares" do
      graph = asker_graph([{:f, 2, {Hologram.Auth, :can?, 3}}])

      assert validate_operations!(
               @declaring_model,
               graph,
               single_ask_plt("{:grant_role, :viewer}")
             ) ==
               :ok
    end

    test "doesn't raise for a computed operation" do
      plt =
        asker_plt(~S"""
        defmodule Hologram.Test.Fixtures.Compiler.OperationAsker do
          def f(user, operation, entity), do: Hologram.Auth.can?(user, operation, entity)
        end
        """)

      graph = asker_graph([{:f, 3, {Hologram.Auth, :can?, 3}}])

      assert validate_operations!([Entity1], graph, plt) == :ok
    end

    test "raises on an operation no entity type declares" do
      graph = asker_graph([{:f, 2, {Hologram.Auth, :can?, 3}}])

      expected_msg =
        "unknown operation :publsh in Hologram.Test.Fixtures.Compiler.OperationAsker.f/2 (line 2) - no entity type declares an allow line for it; the operations this build declares are :archive, :publish, :triage and :unlink, beside the framework's own"

      assert_raise Hologram.CompileError, expected_msg, fn ->
        validate_operations!(@declaring_model, graph, single_ask_plt(":publsh"))
      end
    end

    test "raises on an operation when the model declares none beside the framework's" do
      graph = asker_graph([{:f, 2, {Hologram.Auth, :can?, 3}}])

      expected_msg =
        "unknown operation :publsh in Hologram.Test.Fixtures.Compiler.OperationAsker.f/2 (line 2) - no entity type declares an allow line for it; this build declares no operation beside the framework's own"

      assert_raise Hologram.CompileError, expected_msg, fn ->
        validate_operations!([Entity1], graph, single_ask_plt(":publsh"))
      end
    end

    test "raises on a tuple whose name is not a grant lifecycle operation" do
      graph = asker_graph([{:f, 2, {Hologram.Auth, :can?, 3}}])

      expected_msg =
        "unknown operation {:publish, :editor} in Hologram.Test.Fixtures.Compiler.OperationAsker.f/2 (line 2) - the operation tuples are {:grant_role, role} and {:revoke_role, role}"

      assert_raise Hologram.CompileError, expected_msg, fn ->
        validate_operations!(@declaring_model, graph, single_ask_plt("{:publish, :editor}"))
      end
    end

    test "raises on a role tuple naming a role no entity type declares" do
      graph = asker_graph([{:f, 2, {Hologram.Auth, :can?, 3}}])

      expected_msg =
        "unknown role :editr in {:grant_role, :editr} in Hologram.Test.Fixtures.Compiler.OperationAsker.f/2 (line 2) - declared roles are: :editor, :maintainer, :owner, :viewer"

      assert_raise Hologram.CompileError, expected_msg, fn ->
        validate_operations!(@declaring_model, graph, single_ask_plt("{:grant_role, :editr}"))
      end
    end

    test "raises on a role tuple when no entity type declares a role" do
      graph = asker_graph([{:f, 2, {Hologram.Auth, :can?, 3}}])

      expected_msg =
        "unknown role :editor in {:revoke_role, :editor} in Hologram.Test.Fixtures.Compiler.OperationAsker.f/2 (line 2) - no entity type declares a role"

      assert_raise Hologram.CompileError, expected_msg, fn ->
        validate_operations!([Entity1], graph, single_ask_plt("{:revoke_role, :editor}"))
      end
    end
  end

  describe "validate_prop_usages/2" do
    test "doesn't raise when every required prop is written at the usage" do
      plt = PLT.put(PLT.start(), Module32, IR.for_module(Module32))

      assert validate_prop_usages([Module32], plt) == %{Module32 => MapSet.new([Module31])}
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

      assert validate_prop_usages([Module34], plt) == %{Module34 => MapSet.new([Module31])}
    end

    test "doesn't raise when the required prop is sourced from context" do
      plt = PLT.put(PLT.start(), Module36, IR.for_module(Module36))

      assert validate_prop_usages([Module36], plt) == %{Module36 => MapSet.new([Module35])}
    end

    # A component node is an ordinary 4-tuple, so code outside the template can hold one without any
    # template rendering it.
    test "ignores a component tuple returned by a non-template function" do
      plt = PLT.put(PLT.start(), Module40, IR.for_module(Module40))

      # Nor is it counted among the modules the template uses.
      assert validate_prop_usages([Module40], plt) == %{Module40 => MapSet.new()}
    end

    test "skips modules that are not in the IR PLT" do
      assert validate_prop_usages([Module32], PLT.start()) == %{Module32 => MapSet.new()}
    end

    test "returns the modules each given template uses" do
      plt =
        PLT.start()
        |> PLT.put(Module32, IR.for_module(Module32))
        |> PLT.put(Module38, IR.for_module(Module38))

      assert validate_prop_usages([Module32, Module38], plt) == %{
               Module32 => MapSet.new([Module31]),
               Module38 => MapSet.new([Module37])
             }
    end

    test "doesn't raise when a written value is in the prop's :values list" do
      plt = PLT.put(PLT.start(), Module38, IR.for_module(Module38))

      assert validate_prop_usages([Module38], plt) == %{Module38 => MapSet.new([Module37])}
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

      assert validate_prop_usages([Module38], plt) == %{Module38 => MapSet.new([Module39])}
    end

    # One expression anywhere inside makes the whole composite unknowable until it runs.
    test "doesn't raise when a composite value holds an expression" do
      ir =
        IR.for_code(
          ~s/[{:component, Hologram.Test.Fixtures.Compiler.Module39, [{"size", [expression: {[vars.x]}]}], []}]/,
          %Context{}
        )

      plt = PLT.put(PLT.start(), Module38, module_ir_with_template(ir))

      assert validate_prop_usages([Module38], plt) == %{Module38 => MapSet.new([Module39])}
    end

    test "doesn't raise when the value is not known at compile time" do
      ir =
        IR.for_code(
          ~s/[{:component, Hologram.Test.Fixtures.Compiler.Module37, [{"size", [expression: {vars.x}]}], []}]/,
          %Context{}
        )

      plt = PLT.put(PLT.start(), Module38, module_ir_with_template(ir))

      assert validate_prop_usages([Module38], plt) == %{Module38 => MapSet.new([Module37])}
    end
  end

  describe "usable_bundle?/2" do
    setup do
      static_dir = Path.join([@tmp_dir, "tests", "compiler", "usable_bundle_2"])
      clean_dir(static_dir)

      bundle_path = Path.join(static_dir, "page-kept.js")
      File.write!(bundle_path, "bundle")
      File.write!(bundle_path <> ".map", "map")

      bundle_info = %{
        static_bundle_path: bundle_path,
        static_source_map_path: bundle_path <> ".map"
      }

      [bundle_info: bundle_info, static_dir: static_dir]
    end

    test "a bundle and its source map on disk in the given static dir", %{
      bundle_info: bundle_info,
      static_dir: static_dir
    } do
      assert usable_bundle?(bundle_info, static_dir)
    end

    test "a bundle whose file is gone", %{bundle_info: bundle_info, static_dir: static_dir} do
      File.rm!(bundle_info.static_bundle_path)

      refute usable_bundle?(bundle_info, static_dir)
    end

    test "a bundle whose source map is gone", %{bundle_info: bundle_info, static_dir: static_dir} do
      File.rm!(bundle_info.static_source_map_path)

      refute usable_bundle?(bundle_info, static_dir)
    end

    test "a bundle in another static dir", %{bundle_info: bundle_info} do
      refute usable_bundle?(bundle_info, "/other/static")
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

  # The validation rules live in QueryExtractor's own suite - what is asserted here is the wiring:
  # the components swept are the ones the given pages reach through the call graph.
  describe "validate_slot_bindings!/2" do
    test "passes when every reachable component binds declared slots", %{
      call_graph: call_graph,
      module_info_plt: module_info_plt
    } do
      assert validate_slot_bindings!(page_reach(call_graph), module_info_plt) == :ok
    end

    test "raises when a reachable component binds an undeclared slot", %{
      call_graph: call_graph,
      module_info_plt: module_info_plt
    } do
      patched_call_graph =
        call_graph
        |> CallGraph.clone()
        |> CallGraph.add_edge(
          {PageModule7, :template, 0},
          {ComponentModule11, :template, 0}
        )

      expected_msg =
        "test/elixir/support/fixtures/component/module_11.ex: from_query for prop :entities in Hologram.Test.Fixtures.Component.Module11 binds argument :min_b - no like-named prop is declared"

      reach_by_page = list_reach_by_page([PageModule7], patched_call_graph)

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_slot_bindings!(reach_by_page, module_info_plt)
      end
    end
  end
end
