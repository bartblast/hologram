defmodule Hologram.CompilerTest do
  use Hologram.Test.BasicCase, async: false
  import Hologram.Compiler

  alias Hologram.Commons.PLT
  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Context
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
  alias Hologram.Test.Fixtures.Compiler.Module20
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
  alias Hologram.Test.Fixtures.Compiler.Module41
  alias Hologram.Test.Fixtures.Compiler.Module8
  alias Hologram.Test.Fixtures.Compiler.Module9

  @root_dir Reflection.root_dir()
  @assets_dir Path.join(@root_dir, "assets")
  @js_dir Path.join(@assets_dir, "js")
  @erlang_js_dir Path.join(@js_dir, "erlang")

  @fixtures_compiler_dir Path.join(@fixtures_dir, "compiler")
  @js_fixture_1_path Path.join(@fixtures_compiler_dir, "js_fixture_1.mjs")
  @js_fixture_2_path Path.join(@fixtures_compiler_dir, "js_fixture_2.mjs")
  @tmp_dir Reflection.tmp_dir()

  # How many times the function is called, in any process, while the given function runs.
  defp count_calls(mfa, fun) do
    :erlang.trace_pattern(mfa, true, [:call_count])

    try do
      fun.()
      {:call_count, count} = :erlang.trace_info(mfa, :call_count)
      count
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

  # validate_prop_usages/2 walks a module's template/0, so hand-built DOM IR has to be wrapped the way
  # a compiled module carries it. Built by hand rather than taken from a fixture module, because a
  # fixture with a deliberately invalid usage would fail the compile.hologram Mix task tests.
  # A module info PLT flagging the fixtures that import JavaScript: two that import one file
  # (Module18, Module20), one that imports another (Module22), one that imports a package no
  # node_modules dir holds (Module12) and one that imports two installed packages and a file that
  # does not exist (Module41). Module1 imports nothing.
  defp js_importers_module_info_plt do
    PLT.start(
      items: [
        {Module1, %{js_imports?: false}},
        {Module12, %{js_imports?: true}},
        {Module18, %{js_imports?: true}},
        {Module20, %{js_imports?: true}},
        {Module22, %{js_imports?: true}},
        {Module41, %{js_imports?: true}}
      ]
    )
  end

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

  describe "build_bundle_inputs/2" do
    setup do
      on_exit(fn -> Application.delete_env(:hologram, :client_stacktraces) end)

      test_tmp_dir = Path.join([@tmp_dir, "tests", "compiler", "build_bundle_inputs_2"])
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

    test "names the client stack traces setting", %{
      module_info_plt: module_info_plt,
      opts: opts
    } do
      Application.put_env(:hologram, :client_stacktraces, true)
      assert build_bundle_inputs(module_info_plt, opts).client_stacktraces? == true

      Application.put_env(:hologram, :client_stacktraces, false)
      assert build_bundle_inputs(module_info_plt, opts).client_stacktraces? == false
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

    test "lists every JavaScript source under the js dir with its mtime and size, sorted", %{
      module_info_plt: module_info_plt,
      opts: opts
    } do
      %{js_sources: js_sources} = build_bundle_inputs(module_info_plt, opts)

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

    test "leaves out directories", %{module_info_plt: module_info_plt, opts: opts} do
      %{js_sources: js_sources} = build_bundle_inputs(module_info_plt, opts)

      refute Enum.any?(js_sources, fn {path, _mtime, _size} -> path == "erlang" end)
    end

    test "changes when a JavaScript source changes", %{
      module_info_plt: module_info_plt,
      opts: opts
    } do
      bundle_inputs = build_bundle_inputs(module_info_plt, opts)
      js_source_path = Path.join(opts[:js_dir], "hologram.mjs")
      File.write!(js_source_path, "\n", [:append])

      assert build_bundle_inputs(module_info_plt, opts).js_sources != bundle_inputs.js_sources
    end

    test "changes when package.json changes", %{module_info_plt: module_info_plt, opts: opts} do
      bundle_inputs = build_bundle_inputs(module_info_plt, opts)
      package_json_path = Path.join(opts[:assets_dir], "package.json")
      File.write!(package_json_path, "\n", [:append])

      assert build_bundle_inputs(module_info_plt, opts).package_json_digest !=
               bundle_inputs.package_json_digest
    end

    test "is equal for two calls with nothing changed", %{
      module_info_plt: module_info_plt,
      opts: opts
    } do
      assert build_bundle_inputs(module_info_plt, opts) ==
               build_bundle_inputs(module_info_plt, opts)
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

  describe "build_js_import_digests/1" do
    setup do
      [module_info_plt: js_importers_module_info_plt()]
    end

    test "digests each imported file and each imported package's package.json, by content", %{
      module_info_plt: module_info_plt
    } do
      paths = [
        @js_fixture_1_path,
        @js_fixture_2_path,
        Path.join([@assets_dir, "node_modules", "@sinonjs", "fake-timers", "package.json"]),
        Path.join([@assets_dir, "node_modules", "lodash", "package.json"])
      ]

      expected = Map.new(paths, &{&1, :erlang.phash2(File.read!(&1))})

      assert build_js_import_digests(module_info_plt) == expected
    end

    test "leaves out a package no node_modules dir holds", %{module_info_plt: module_info_plt} do
      paths =
        module_info_plt
        |> build_js_import_digests()
        |> Map.keys()

      refute Enum.any?(paths, &String.contains?(&1, "chart.js"))
    end

    test "leaves out an imported file that does not exist", %{module_info_plt: module_info_plt} do
      paths =
        module_info_plt
        |> build_js_import_digests()
        |> Map.keys()

      refute Enum.any?(paths, &String.ends_with?(&1, "missing_js_fixture.mjs"))
    end

    test "asks only the modules the module info PLT flags as importers" do
      module_info_plt = PLT.start(items: [{Module18, %{js_imports?: false}}])

      assert build_js_import_digests(module_info_plt) == %{}
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

  describe "build_runtime_js/6" do
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
      assert checks_with_plt == 0
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

      js = build_runtime_js(runtime_mfas, ir_plt, encode_plt, MapSet.new(), [], js_dir: @js_dir)

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

      js = build_runtime_js(runtime_mfas, ir_plt, encode_plt, MapSet.new(), [], js_dir: @js_dir)

      assert js =~ ~r/globalThis\.Hologram\.config = \{errorOverlay: \w+, liveReload: false, /
    end

    test "no JS imports", %{encode_plt: encode_plt, ir_plt: ir_plt, runtime_mfas: runtime_mfas} do
      mfas = reject_js_import_mfas(runtime_mfas)

      js = build_runtime_js(mfas, ir_plt, encode_plt, MapSet.new(), [], js_dir: @js_dir)

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
        esbuild_bin_path: Path.join([node_modules_path, ".bin", "esbuild"]),
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

    test "the same entry file bundles to the same digest" do
      node_modules_path = Path.join([@root_dir, "assets", "node_modules"])

      tmp_dir =
        Path.join([Reflection.tmp_dir(), "tests", "compiler", "bundle_4_same_digest"])

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

      assert %{digest: digest} = bundle(MyPage, entry_file_path, "my_bundle_name", opts)
      assert %{digest: ^digest} = bundle(MyPage, entry_file_path, "my_bundle_name", opts)
    end

    test "a bundle left in the output dir by an earlier run is not picked up" do
      node_modules_path = Path.join([@root_dir, "assets", "node_modules"])

      tmp_dir =
        Path.join([Reflection.tmp_dir(), "tests", "compiler", "bundle_4_stale_output"])

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
      js = build_runtime_js(runtime_mfas, ir_plt, PLT.start(), MapSet.new(), [], js_dir: @js_dir)

      assert String.contains?(js, "globalThis.Hologram.config = #{client_config()};")
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

  describe "list_changed_js_importers/3" do
    setup do
      module_info_plt = js_importers_module_info_plt()

      [digests: build_js_import_digests(module_info_plt), module_info_plt: module_info_plt]
    end

    test "a changed file lists its importers", %{
      digests: digests,
      module_info_plt: module_info_plt
    } do
      kept_digests = Map.update!(digests, @js_fixture_1_path, &(&1 + 1))

      assert list_changed_js_importers(kept_digests, digests, module_info_plt) == [
               Module18,
               Module20
             ]
    end

    test "a changed package lists its importers", %{
      digests: digests,
      module_info_plt: module_info_plt
    } do
      package_json_path = Path.join([@assets_dir, "node_modules", "lodash", "package.json"])
      kept_digests = Map.update!(digests, package_json_path, &(&1 + 1))

      assert list_changed_js_importers(kept_digests, digests, module_info_plt) == [Module41]
    end

    test "a source only the kept digests have lists its importers", %{
      digests: digests,
      module_info_plt: module_info_plt
    } do
      new_digests = Map.delete(digests, @js_fixture_2_path)

      assert list_changed_js_importers(digests, new_digests, module_info_plt) == [Module22]
    end

    test "a source only the new digests have lists its importers", %{
      digests: digests,
      module_info_plt: module_info_plt
    } do
      kept_digests = Map.delete(digests, @js_fixture_2_path)

      assert list_changed_js_importers(kept_digests, digests, module_info_plt) == [Module22]
    end

    test "unchanged digests list nobody", %{digests: digests, module_info_plt: module_info_plt} do
      assert list_changed_js_importers(digests, digests, module_info_plt) == []
    end

    test "no kept digests list nobody", %{digests: digests, module_info_plt: module_info_plt} do
      assert list_changed_js_importers(nil, digests, module_info_plt) == []
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

  describe "list_mfas_by_page/2" do
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

  describe "list_mfas_by_page/4" do
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

  describe "partition_affected_pages/5" do
    setup do
      test_tmp_dir = Path.join([@tmp_dir, "tests", "compiler", "partition_affected_pages_5"])
      clean_dir(test_tmp_dir)

      bundle_path = Path.join(test_tmp_dir, "page-kept.js")
      File.write!(bundle_path, "bundle")
      File.write!(bundle_path <> ".map", "map")

      page_state = fn modules, path ->
        %{
          bundle_info: %{static_bundle_path: path, static_source_map_path: path <> ".map"},
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

    test "a page with no kept state is rebuilt", %{pages_plt: pages_plt, static_dir: static_dir} do
      assert partition_affected_pages(
               [Module1],
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

      assert result == {empty_diff, false}
      assert PLT.get!(plt, Hologram.Reflection) == old_info
    end

    test "reads a compiled module and reports an edit when its digest moved", %{
      empty_diff: empty_diff
    } do
      beam_path = :code.which(Hologram.Reflection)

      plt =
        PLT.put(PLT.start(), Hologram.Reflection, %{Reflection.beam_info(beam_path) | digest: 1})

      result =
        patch_module_info_plt!(
          plt,
          nil,
          MapSet.new([Hologram.Reflection]),
          [{Hologram.Reflection, beam_path}],
          MapSet.new([Hologram.Reflection])
        )

      assert result == {%{empty_diff | edited_modules: [Hologram.Reflection]}, true}
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

      assert result == {empty_diff, false}
    end

    test "reports a change but no edit when only the mtime moved", %{empty_diff: empty_diff} do
      beam_path = :code.which(Hologram.Reflection)

      plt =
        PLT.put(PLT.start(), Hologram.Reflection, %{Reflection.beam_info(beam_path) | mtime: 0})

      result =
        patch_module_info_plt!(
          plt,
          nil,
          MapSet.new([Hologram.Reflection]),
          [{Hologram.Reflection, beam_path}],
          MapSet.new([Hologram.Reflection])
        )

      assert result == {empty_diff, true}
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

      assert result == {%{empty_diff | added_modules: [Hologram.Reflection]}, true}
      assert PLT.get!(plt, Hologram.Reflection) == Reflection.beam_info(beam_path)
    end

    test "removes an editable module whose beam is gone", %{empty_diff: empty_diff} do
      plt = PLT.put(PLT.start(), :removed_module, %{digest: "removed"})

      result = patch_module_info_plt!(plt, nil, MapSet.new([:removed_module]), [], MapSet.new())

      assert result == {%{empty_diff | removed_modules: [:removed_module]}, true}
      assert PLT.get(plt, :removed_module) == :error
    end

    test "checks a module that left the listing while the VM still has its beam", %{
      empty_diff: empty_diff
    } do
      # A consolidated protocol whose directory is off the code path for a moment is listed nowhere,
      # yet the VM loads it from another beam.
      beam_path = :code.which(Hologram.Reflection)

      plt =
        PLT.put(PLT.start(), Hologram.Reflection, %{Reflection.beam_info(beam_path) | digest: 1})

      result =
        patch_module_info_plt!(plt, nil, MapSet.new([Hologram.Reflection]), [], MapSet.new())

      assert result == {%{empty_diff | edited_modules: [Hologram.Reflection]}, true}
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

      plt = PLT.put(PLT.start(), module, %{digest: 1})

      result = patch_module_info_plt!(plt, nil, MapSet.new([module]), [], MapSet.new())

      assert result == {%{empty_diff | removed_modules: [module]}, true}
      assert PLT.get(plt, module) == :error
    end

    test "checks the beam of a protocol the compiler did not report", %{empty_diff: empty_diff} do
      beam_path = :code.which(Enumerable)

      plt =
        PLT.put(PLT.start(), Enumerable, %{Reflection.beam_info(beam_path) | digest: 1, mtime: 0})

      result =
        patch_module_info_plt!(
          plt,
          nil,
          MapSet.new([Enumerable]),
          [{Enumerable, beam_path}],
          MapSet.new()
        )

      assert result == {%{empty_diff | edited_modules: [Enumerable]}, true}
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

      assert result == {empty_diff, false}
      assert PLT.get!(plt, Enumerable) == old_info
    end

    test "leaves every entry as the beams and the reported modules say, and finds the diff" do
      reflection_path = :code.which(Hologram.Reflection)
      compiler_path = :code.which(Hologram.Compiler)
      enumerable_path = :code.which(Enumerable)

      plt_path = :code.which(Hologram.Commons.PLT)
      kept_reflection_info = %{Reflection.beam_info(reflection_path) | digest: 1, mtime: 0}

      plt =
        PLT.put(PLT.start(), [
          # Not editable.
          {Enum, %{digest: "kept"}},
          # Editable, not reported, mtime moved: left as it is.
          {Hologram.Reflection, kept_reflection_info},
          # Reported: read again.
          {Hologram.Compiler, %{Reflection.beam_info(compiler_path) | digest: 1}},
          # A protocol not reported, mtime moved: read again.
          {Enumerable, %{Reflection.beam_info(enumerable_path) | digest: 1, mtime: 0}},
          # Editable, no beam: removed.
          {:removed_module, %{digest: "removed"}}
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

      {diff, changed?} =
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

  test "prune_module_def/4 prunes protocol dispatcher clauses to included implementations", %{
    module_info_plt: module_info_plt
  } do
    module_mfas = [
      {String.Chars, :impl_for, 1},
      {String.Chars, :impl_for!, 1},
      {String.Chars, :struct_impl_for, 1},
      {String.Chars, :to_string, 1}
    ]

    reachable_modules = MapSet.new([String.Chars, String.Chars.Atom, String.Chars.URI])

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
    assert String.contains?(js, ~s/Type.atom("Elixir.String.Chars.URI")/)

    refute String.contains?(js, "Elixir.String.Chars.Version")
    refute String.contains?(js, "Hologram.Test.Fixtures.Compiler.CallGraph.Module12")
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
end
