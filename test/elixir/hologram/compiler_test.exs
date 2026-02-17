defmodule Hologram.CompilerTest do
  use Hologram.Test.BasicCase, async: false
  import Hologram.Compiler

  alias Hologram.Commons.PLT
  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Digraph
  alias Hologram.Compiler.IR
  alias Hologram.Reflection

  alias Hologram.Test.Fixtures.Compiler.Module1
  alias Hologram.Test.Fixtures.Compiler.Module11
  alias Hologram.Test.Fixtures.Compiler.Module12
  alias Hologram.Test.Fixtures.Compiler.Module13
  alias Hologram.Test.Fixtures.Compiler.Module14
  alias Hologram.Test.Fixtures.Compiler.Module15
  alias Hologram.Test.Fixtures.Compiler.Module17
  alias Hologram.Test.Fixtures.Compiler.Module2
  alias Hologram.Test.Fixtures.Compiler.Module3
  alias Hologram.Test.Fixtures.Compiler.Module4
  alias Hologram.Test.Fixtures.Compiler.Module8
  alias Hologram.Test.Fixtures.Compiler.Module9

  @root_dir Reflection.root_dir()
  @assets_dir Path.join(@root_dir, "assets")
  @js_dir Path.join(@assets_dir, "js")
  @erlang_js_dir Path.join(@js_dir, "erlang")

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
      runtime_mfas: CallGraph.list_runtime_mfas(call_graph)
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
                 %{from: "./utils.js", export: "formatDate", alias: "$1"},
                 %{from: "chart.js", export: "Chart", alias: "$2"},
                 %{from: "chart.js", export: "helpers", alias: "$3"}
               ],
               bindings: %{
                 Module12 => %{
                   "MyChart" => "$2",
                   "helpers" => "$3"
                 },
                 Module17 => %{
                   "myFormatDate" => "$1"
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

  describe "build_page_js/3" do
    setup %{call_graph: call_graph, runtime_mfas: runtime_mfas} do
      call_graph_without_runtime_mfas =
        call_graph
        |> CallGraph.clone()
        |> CallGraph.remove_runtime_mfas!(runtime_mfas)

      [call_graph: call_graph_without_runtime_mfas]
    end

    test "has both Erlang and Elixir function defs", %{call_graph: call_graph, ir_plt: ir_plt} do
      result = build_page_js(Module9, call_graph, ir_plt, @js_dir)

      js_fragment_1 = ~s/globalThis.hologram.pageReachableFunctionDefs/
      js_fragment_2 = ~s/Interpreter.defineElixirFunction/
      js_fragment_3 = ~s/Interpreter.defineErlangFunction/

      assert String.contains?(result, js_fragment_1)
      assert String.contains?(result, js_fragment_2)
      assert String.contains?(result, js_fragment_3)
    end

    test "has only Elixir defs", %{call_graph: call_graph, ir_plt: ir_plt} do
      result = build_page_js(Module11, call_graph, ir_plt, @js_dir)

      js_fragment_1 = ~s/globalThis.hologram.pageReachableFunctionDefs/
      js_fragment_2 = ~s/Interpreter.defineElixirFunction/
      js_fragment_3 = ~s/Interpreter.defineErlangFunction/

      assert String.contains?(result, js_fragment_1)
      assert String.contains?(result, js_fragment_2)
      refute String.contains?(result, js_fragment_3)
    end
  end

  test "build_call_graph/0" do
    assert %CallGraph{} = call_graph = build_call_graph()
    assert CallGraph.has_vertex?(call_graph, {Compiler, :build_call_graph, 1})
  end

  test "build_call_graph/1", %{ir_plt: ir_plt} do
    assert %CallGraph{} = call_graph = build_call_graph(ir_plt)
    assert CallGraph.has_vertex?(call_graph, {Compiler, :build_call_graph, 1})
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
             ~s/Interpreter.defineNotImplementedErlangFunction("application", "get_application", 1/
           )
  end

  test "bundle/2" do
    tmp_dir = Path.join([Reflection.tmp_dir(), "tests", "compiler", "bundle_2"])

    opts = [
      esbuild_bin_path: Path.join([@root_dir, "assets", "node_modules", ".bin", "esbuild"]),
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
      tmp_dir =
        Path.join([Reflection.tmp_dir(), "tests", "compiler", "bundle_4_valid_entry_file"])

      opts = [
        esbuild_bin_path: Path.join([@root_dir, "assets", "node_modules", ".bin", "esbuild"]),
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
      tmp_dir =
        Path.join([Reflection.tmp_dir(), "tests", "compiler", "bundle_4_invalid_entry_file"])

      opts = [
        esbuild_bin_path: Path.join([@root_dir, "assets", "node_modules", ".bin", "esbuild"]),
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
      tmp_dir =
        Path.join([Reflection.tmp_dir(), "tests", "compiler", "bundle_4_exceeds_max_size"])

      opts = [
        esbuild_bin_path: Path.join([@root_dir, "assets", "node_modules", ".bin", "esbuild"]),
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

  test "create_page_entry_files/4", %{
    call_graph: call_graph,
    ir_plt: ir_plt,
    runtime_mfas: runtime_mfas
  } do
    opts = [
      js_dir: @js_dir,
      tmp_dir: Path.join([@tmp_dir, "tests", "compiler", "create_page_entry_files_4"])
    ]

    clean_dir(opts[:tmp_dir])

    page_modules = Reflection.list_pages()

    call_graph_without_runtime_mfas =
      call_graph
      |> CallGraph.clone()
      |> CallGraph.remove_runtime_mfas!(runtime_mfas)

    result = create_page_entry_files(page_modules, call_graph_without_runtime_mfas, ir_plt, opts)

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

  test "create_runtime_entry_file/3", %{ir_plt: ir_plt, runtime_mfas: runtime_mfas} do
    opts = [
      js_dir: @js_dir,
      tmp_dir: Path.join([@tmp_dir, "tests", "compiler", "create_runtime_entry_file_3"])
    ]

    clean_dir(opts[:tmp_dir])

    entry_file_path = create_runtime_entry_file(runtime_mfas, ir_plt, opts)

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

  describe "format_files/2" do
    @unformatted_valid_js_code "const myVar  =  123"
    @formatted_valid_js_code "const myVar = 123;\n"

    test "valid JS code" do
      test_tmp_dir =
        Path.join([@tmp_dir, "tests", "compiler", "format_files_2_valid_input_files"])

      clean_dir(test_tmp_dir)

      file_path_1 = Path.join(test_tmp_dir, "file_1.js")
      File.write!(file_path_1, @unformatted_valid_js_code)

      file_path_2 = Path.join(test_tmp_dir, "file_2.js")
      File.write!(file_path_2, @unformatted_valid_js_code)

      opts = [
        assets_dir: @assets_dir,
        formatter_bin_path: Path.join([@assets_dir, "node_modules", ".bin", "biome"])
      ]

      assert Compiler.format_files([file_path_1, file_path_2], opts) =~
               ~r"Formatted 2 files in [0-9]+[mµ]?s\. Fixed 2 files\.\n"u

      assert File.read!(file_path_1) == @formatted_valid_js_code
      assert File.read!(file_path_2) == @formatted_valid_js_code
    end

    test "invalid JS code" do
      test_tmp_dir = Path.join([@tmp_dir, "tests", "compiler", "format_files_2_invalid_js_code"])

      clean_dir(test_tmp_dir)

      unformatted_invalid_js_code = "const myVar  123"

      file_path_1 = Path.join(test_tmp_dir, "file_1.js")
      File.write!(file_path_1, unformatted_invalid_js_code)

      file_path_2 = Path.join(test_tmp_dir, "file_2.js")
      File.write!(file_path_2, @unformatted_valid_js_code)

      opts = [
        assets_dir: @assets_dir,
        formatter_bin_path: Path.join([@assets_dir, "node_modules", ".bin", "biome"])
      ]

      assert_raise RuntimeError,
                   "Biome formatter failed (probably there were JavaScript syntax errors)",
                   fn ->
                     Compiler.format_files([file_path_1, file_path_2], opts)
                   end

      assert File.read!(file_path_1) == unformatted_invalid_js_code
      assert File.read!(file_path_2) == @formatted_valid_js_code
    end
  end

  describe "get_erlang_function_js/4" do
    test ":erlang module function that is implemented" do
      result = get_erlang_function_js(:erlang, :+, 2, @erlang_js_dir)

      expected =
        normalize_newlines("""
        (left, right) => {
            if (!Type.isNumber(left) || !Type.isNumber(right)) {
              const blame = `${Interpreter.inspect(left)} + ${Interpreter.inspect(right)}`;
              Interpreter.raiseArithmeticError(blame);
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
            const value = Erlang_Maps["get/3"](key, map, null);

            if (value !== null) {
              return value;
            }

            Interpreter.raiseKeyError(Interpreter.buildKeyErrorMsg(key, map));
          }\
        """)

      assert normalize_newlines(result) == expected
    end

    test ":maps module function that is not implemented" do
      result = Compiler.get_erlang_function_js(:maps, :not_implemented, 2, @erlang_js_dir)
      assert result == nil
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
                     params: [%IR.Variable{name: :x, version: 0}],
                     guards: [],
                     body: %IR.Block{
                       expressions: [%IR.Variable{name: :x, version: 0}]
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
end
