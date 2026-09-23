defmodule Hologram.Compiler.CacheTest do
  use Hologram.Test.BasicCase, async: false
  import Hologram.Compiler.Cache

  alias Hologram.Commons.PLT
  alias Hologram.Commons.SerializationUtils
  alias Hologram.Compiler.Cache
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Tracer
  alias Hologram.Reflection

  setup do
    stop_cache()
    on_exit(&stop_cache/0)
  end

  defp page_state_reading(js_inputs) do
    %{bundle_info: %{digest: "a", js_inputs: js_inputs}, modules: MapSet.new()}
  end

  # Puts a value into every field the compile state dump holds.
  defp put_full_state do
    put_app_versions(hologram: "1.0.0")
    put_bundle_inputs(%{client_stacktraces?: true})
    put_encoding_inputs(%{async_mfas: MapSet.new(), client_stacktraces?: true})
    put_module_metadata(%{Module1 => %{app: :hologram, file: "lib/module_1.ex"}})

    put_page(
      Module1,
      %{
        bundle_info: %{digest: "a", js_inputs: %{"/app/assets/js/page.mjs" => {:digest, 1}}},
        modules: MapSet.new([Module1])
      },
      [
        {Module1, :fun_1, 0}
      ]
    )

    put_pending_pages([Module2])

    put_runtime(%{
      app_versions: [hologram: "1.0.0"],
      bundle_info: %{digest: "b", js_inputs: %{"/app/assets/js/runtime.mjs" => {:digest, 2}}},
      js_binding_modules: MapSet.new(),
      mfas: [{Module1, :fun_1, 0}]
    })

    put_template_modules(%{Module1 => MapSet.new()})
  end

  # One put per field the compile state dump holds, each with a value the empty cache does not hold.
  defp put_new_values do
    [
      fn -> put_app_versions(hologram: "1.0.0") end,
      fn -> put_bundle_inputs(%{client_stacktraces?: true}) end,
      fn -> put_encoding_inputs(%{async_mfas: MapSet.new(), client_stacktraces?: true}) end,
      fn -> put_module_metadata(%{Module1 => %{app: :hologram, file: "lib/module_1.ex"}}) end,
      fn -> put_pending_pages([Module1]) end,
      fn ->
        put_runtime(%{
          app_versions: [],
          bundle_info: %{js_inputs: %{}},
          js_binding_modules: MapSet.new(),
          mfas: []
        })
      end,
      fn -> put_template_modules(%{Module1 => MapSet.new()}) end
    ]
  end

  defp read_compile_state_dump(path) do
    path
    |> File.read!()
    |> SerializationUtils.deserialize(true)
  end

  defp runtime_state_reading(js_inputs) do
    %{
      app_versions: [],
      bundle_info: %{digest: "b", js_inputs: js_inputs},
      js_binding_modules: MapSet.new(),
      mfas: []
    }
  end

  defp stop_cache do
    if Process.whereis(Cache), do: GenServer.stop(Cache)
  end

  describe "clear_module_infos/0" do
    test "forgets the dump time and the editable modules, and keeps the module infos" do
      %{module_info_plt: module_info_plt} = get()
      PLT.put(module_info_plt, Module1, %{digest: "a"})
      put_module_infos(123, MapSet.new([Module1]))

      assert clear_module_infos() == :ok
      assert %{dumped_at: nil, editable_modules: nil, module_info_plt: ^module_info_plt} = get()
      assert PLT.get(module_info_plt, Module1) == {:ok, %{digest: "a"}}
    end

    test "keeps the pending pages" do
      put_pending_pages([Module1])

      clear_module_infos()

      assert get().pending_pages == MapSet.new([Module1])
    end

    test "keeps the call graph and the IR PLT" do
      %{call_graph: call_graph, ir_plt: ir_plt} = get()
      CallGraph.add_vertex(call_graph, {Module1, :fun_1, 0})
      PLT.put(ir_plt, Module1, :ir_1)
      assert CallGraph.has_vertex?(call_graph, {Module1, :fun_1, 0})

      clear_module_infos()

      assert %{call_graph: ^call_graph, ir_plt: ^ir_plt} = get()
      assert CallGraph.has_vertex?(call_graph, {Module1, :fun_1, 0})
      assert PLT.get(ir_plt, Module1) == {:ok, :ir_1}
    end

    test "keeps the encode PLT and the encoding inputs" do
      %{encode_plt: encode_plt} = get()
      PLT.put(encode_plt, {Module1, :fun_1, 0}, "js")
      encoding_inputs = %{async_mfas: MapSet.new(), client_stacktraces?: true}
      put_encoding_inputs(encoding_inputs)

      clear_module_infos()

      assert %{encode_plt: ^encode_plt, encoding_inputs: ^encoding_inputs} = get()
      assert PLT.get(encode_plt, {Module1, :fun_1, 0}) == {:ok, "js"}
    end

    test "keeps the module metadata" do
      module_metadata = %{Module1 => %{app: :hologram, file: "lib/module_1.ex"}}
      put_module_metadata(module_metadata)

      clear_module_infos()

      assert get().module_metadata == module_metadata
    end

    test "keeps the template modules" do
      template_modules = %{Module1 => MapSet.new([Module2])}
      put_template_modules(template_modules)

      clear_module_infos()

      assert get().template_modules == template_modules
    end

    test "keeps the bundle inputs" do
      bundle_inputs = %{client_stacktraces?: true, package_json_digest: "a"}
      put_bundle_inputs(bundle_inputs)

      clear_module_infos()

      assert get().bundle_inputs == bundle_inputs
    end
  end

  describe "compile_state_changed?" do
    setup do
      dump_dir = Path.join([Reflection.tmp_dir(), "tests", "compiler", "cache", "changed"])
      clean_dir(dump_dir)

      [path: Path.join(dump_dir, "compile_state.bin")]
    end

    test "is clear at first" do
      refute get().compile_state_changed?
    end

    test "is set by a put of a value that differs from the kept one" do
      Enum.each(put_new_values(), fn put ->
        stop_cache()
        put.()

        assert get().compile_state_changed?
      end)
    end

    test "is left clear by a put of the value already kept", %{path: path} do
      Enum.each(put_new_values(), fn put -> put.() end)
      dump_compile_state(path, false)

      Enum.each(put_new_values(), fn put -> put.() end)

      refute get().compile_state_changed?
    end

    test "is set by put_page/3", %{path: path} do
      dump_compile_state(path, false)

      put_page(Module1, %{bundle_info: %{digest: "a", js_inputs: %{}}, modules: MapSet.new()}, [])

      assert get().compile_state_changed?
    end

    test "is set by delete_page/1", %{path: path} do
      dump_compile_state(path, false)

      delete_page(Module1)

      assert get().compile_state_changed?
    end

    test "is set by delete_pending_pages/1 of a pending page", %{path: path} do
      put_pending_pages([Module1])
      dump_compile_state(path, false)

      delete_pending_pages([Module1])

      assert get().compile_state_changed?
    end

    test "is left clear by delete_pending_pages/1 of a page that is not pending", %{path: path} do
      dump_compile_state(path, false)

      delete_pending_pages([Module1])

      refute get().compile_state_changed?
    end

    test "is set by forget_bundles/0", %{path: path} do
      dump_compile_state(path, false)

      forget_bundles()

      assert get().compile_state_changed?
    end

    test "is left clear by put_module_infos/2", %{path: path} do
      dump_compile_state(path, false)

      put_module_infos(123, MapSet.new([Module1]))

      refute get().compile_state_changed?
    end

    test "is kept by clear_module_infos/0" do
      put_pending_pages([Module1])

      clear_module_infos()

      assert get().compile_state_changed?
    end
  end

  describe "delete_page/2" do
    test "forgets a kept page" do
      put_page(Module1, %{bundle_info: %{digest: "a", js_inputs: %{}}, modules: MapSet.new()}, [])

      assert delete_page(Module1) == :ok
      assert PLT.get(get().pages_plt, Module1) == :error
      assert PLT.get(get().page_mfas_plt, Module1) == :error
    end

    test "a page that was never kept" do
      assert delete_page(Module1) == :ok
    end
  end

  describe "delete_pending_pages/1" do
    test "forgets the given pages and keeps the rest" do
      put_pending_pages([Module1, Module2, Module3])

      assert delete_pending_pages([Module1, Module3]) == :ok
      assert get().pending_pages == MapSet.new([Module2])
    end

    test "a page that is not pending" do
      put_pending_pages([Module1])

      assert delete_pending_pages([Module2]) == :ok
      assert get().pending_pages == MapSet.new([Module1])
    end
  end

  describe "dump_compile_state/2" do
    setup do
      dump_dir =
        Path.join([Reflection.tmp_dir(), "tests", "compiler", "cache", "dump_compile_state_2"])

      clean_dir(dump_dir)

      [path: Path.join(dump_dir, "compile_state.bin")]
    end

    test "writes the kept state", %{path: path} do
      put_full_state()

      assert dump_compile_state(path, false) == :written

      assert read_compile_state_dump(path) ==
               {1,
                %{
                  app_versions: [hologram: "1.0.0"],
                  bundle_inputs: %{client_stacktraces?: true},
                  encoding_inputs: %{async_mfas: MapSet.new(), client_stacktraces?: true},
                  js_input_paths:
                    MapSet.new(["/app/assets/js/page.mjs", "/app/assets/js/runtime.mjs"]),
                  module_metadata: %{Module1 => %{app: :hologram, file: "lib/module_1.ex"}},
                  pages: %{
                    Module1 => %{
                      bundle_info: %{
                        digest: "a",
                        js_inputs: %{"/app/assets/js/page.mjs" => {:digest, 1}}
                      },
                      modules: MapSet.new([Module1])
                    }
                  },
                  pending_pages: MapSet.new([Module2]),
                  runtime: %{
                    app_versions: [hologram: "1.0.0"],
                    bundle_info: %{
                      digest: "b",
                      js_inputs: %{"/app/assets/js/runtime.mjs" => {:digest, 2}}
                    },
                    js_binding_modules: MapSet.new(),
                    mfas: [{Module1, :fun_1, 0}]
                  },
                  template_modules: %{Module1 => MapSet.new()}
                }}
    end

    test "leaves out the page MFA lists", %{path: path} do
      put_full_state()

      dump_compile_state(path, false)

      {1, compile_state} = read_compile_state_dump(path)
      refute Map.has_key?(compile_state, :page_mfas)
    end

    test "marks the compile state as unchanged", %{path: path} do
      put_full_state()

      dump_compile_state(path, false)

      refute get().compile_state_changed?
    end

    test "writes nothing when the state is the one last written", %{path: path} do
      put_full_state()
      dump_compile_state(path, false)
      File.write!(path, "untouched")

      assert dump_compile_state(path, false) == :unchanged
      assert File.read!(path) == "untouched"
    end

    test "writes again when the state changed", %{path: path} do
      put_full_state()
      dump_compile_state(path, false)
      put_pending_pages([Module3])

      assert dump_compile_state(path, false) == :written

      {1, compile_state} = read_compile_state_dump(path)
      assert compile_state.pending_pages == MapSet.new([Module3])
    end

    test "writes when forced", %{path: path} do
      put_full_state()
      dump_compile_state(path, false)
      File.write!(path, "stale")

      assert dump_compile_state(path, true) == :written
      assert {1, _compile_state} = read_compile_state_dump(path)
    end

    test "creates the path's directory", %{path: path} do
      nested_path = Path.join([Path.dirname(path), "dir_1", "dir_2", "compile_state.bin"])

      assert dump_compile_state(nested_path, true) == :written
      assert File.exists?(nested_path)
    end
  end

  describe "forget_bundles/0" do
    test "empties the page states, the MFA lists and the encode PLT, and keeps their processes" do
      %{encode_plt: encode_plt, page_mfas_plt: page_mfas_plt, pages_plt: pages_plt} = get()
      put_page(Module1, %{bundle_info: %{digest: "a", js_inputs: %{}}, modules: MapSet.new()}, [])
      PLT.put(encode_plt, {Module1, :fun_1, 0}, "js")

      assert forget_bundles() == :ok

      assert %{encode_plt: ^encode_plt, page_mfas_plt: ^page_mfas_plt, pages_plt: ^pages_plt} =
               get()

      assert Process.alive?(encode_plt.pid)
      assert Process.alive?(page_mfas_plt.pid)
      assert Process.alive?(pages_plt.pid)
      assert PLT.keys(encode_plt) == []
      assert PLT.keys(page_mfas_plt) == []
      assert PLT.keys(pages_plt) == []
    end

    test "forgets the pending pages, the runtime, the template modules and the encoding inputs" do
      put_encoding_inputs(%{async_mfas: MapSet.new(), client_stacktraces?: true})
      put_pending_pages([Module1])
      put_template_modules(%{Module1 => MapSet.new()})

      put_runtime(%{
        app_versions: [],
        bundle_info: %{js_inputs: %{}},
        js_binding_modules: MapSet.new(),
        mfas: []
      })

      forget_bundles()

      assert %{encoding_inputs: nil, runtime: nil, template_modules: nil} = get()

      assert get().pending_pages == MapSet.new()
    end

    test "keeps the call graph, the IR PLT, the module infos, the module metadata, the app versions and the bundle inputs" do
      %{call_graph: call_graph, ir_plt: ir_plt, module_info_plt: module_info_plt} = get()
      CallGraph.add_vertex(call_graph, {Module1, :fun_1, 0})
      PLT.put(ir_plt, Module1, :ir_1)
      PLT.put(module_info_plt, Module1, %{digest: "a"})
      put_module_infos(123, MapSet.new([Module1]))
      put_app_versions(hologram: "1.0.0")
      bundle_inputs = %{client_stacktraces?: true}
      put_bundle_inputs(bundle_inputs)
      module_metadata = %{Module1 => %{app: :hologram, file: "lib/module_1.ex"}}
      put_module_metadata(module_metadata)

      forget_bundles()

      assert %{
               app_versions: [hologram: "1.0.0"],
               bundle_inputs: ^bundle_inputs,
               call_graph: ^call_graph,
               dumped_at: 123,
               ir_plt: ^ir_plt,
               module_info_plt: ^module_info_plt,
               module_metadata: ^module_metadata
             } = get()

      assert CallGraph.has_vertex?(call_graph, {Module1, :fun_1, 0})
      assert PLT.get(ir_plt, Module1) == {:ok, :ir_1}
      assert PLT.get(module_info_plt, Module1) == {:ok, %{digest: "a"}}
      assert get().editable_modules == MapSet.new([Module1])
    end
  end

  describe "get/0" do
    test "starts the cache on first use" do
      refute Process.whereis(Cache)

      get()

      assert is_pid(Process.whereis(Cache))
    end

    test "registers the tracer, with its table owned by the cache" do
      tracers = Code.get_compiler_option(:tracers)
      on_exit(fn -> Code.put_compiler_option(:tracers, tracers) end)
      Code.put_compiler_option(:tracers, tracers -- [Tracer])

      get()

      assert Tracer in Code.get_compiler_option(:tracers)
      assert :ets.info(Tracer, :owner) == Process.whereis(Cache)
    end

    test "returns empty kept state at first" do
      assert %{
               bundle_inputs: nil,
               call_graph: %CallGraph{} = call_graph,
               compile_state_changed?: false,
               dumped_at: nil,
               editable_modules: nil,
               encode_plt: %PLT{} = encode_plt,
               encoding_inputs: nil,
               ir_plt: %PLT{} = ir_plt,
               module_info_plt: %PLT{} = module_info_plt,
               module_metadata: nil,
               page_mfas_plt: %PLT{} = page_mfas_plt,
               pages_plt: %PLT{} = pages_plt,
               pending_pages: pending_pages,
               runtime: nil,
               template_modules: nil
             } = get()

      assert pending_pages == MapSet.new()

      assert CallGraph.vertices(call_graph) == []
      assert PLT.keys(encode_plt) == []
      assert PLT.keys(ir_plt) == []
      assert PLT.keys(module_info_plt) == []
      assert PLT.keys(page_mfas_plt) == []
      assert PLT.keys(pages_plt) == []
    end

    test "returns the same call graph and PLTs on every call" do
      %{
        call_graph: call_graph,
        encode_plt: encode_plt,
        ir_plt: ir_plt,
        module_info_plt: module_info_plt,
        page_mfas_plt: page_mfas_plt,
        pages_plt: pages_plt
      } = get()

      assert %{
               call_graph: ^call_graph,
               encode_plt: ^encode_plt,
               ir_plt: ^ir_plt,
               module_info_plt: ^module_info_plt,
               page_mfas_plt: ^page_mfas_plt,
               pages_plt: ^pages_plt
             } = get()
    end

    test "doesn't link the cache to the caller" do
      task = Task.async(&get/0)
      Task.await(task)

      cache_pid = Process.whereis(Cache)
      assert {:links, links} = Process.info(cache_pid, :links)
      refute task.pid in links

      Process.exit(task.pid, :kill)

      assert Process.alive?(cache_pid)
    end
  end

  describe "js_input_paths" do
    test "is empty at first" do
      assert get().js_input_paths == MapSet.new()
    end

    test "gets the paths of the files a kept page's bundle read" do
      put_page(Module1, page_state_reading(%{"/app/a.mjs" => {:digest, 1}}), [])
      put_page(Module2, page_state_reading(%{"/app/b.mjs" => {:digest, 2}}), [])

      assert get().js_input_paths == MapSet.new(["/app/a.mjs", "/app/b.mjs"])
    end

    test "gets the paths of the files the kept runtime's bundle read" do
      put_runtime(runtime_state_reading(%{"/app/runtime.mjs" => {:digest, 3}}))

      assert get().js_input_paths == MapSet.new(["/app/runtime.mjs"])
    end

    test "holds a path two bundles read once" do
      put_page(Module1, page_state_reading(%{"/app/a.mjs" => {:digest, 1}}), [])
      put_page(Module2, page_state_reading(%{"/app/a.mjs" => {:digest, 2}}), [])

      assert get().js_input_paths == MapSet.new(["/app/a.mjs"])
    end

    test "keeps the paths when the runtime is forgotten" do
      put_runtime(runtime_state_reading(%{"/app/runtime.mjs" => {:digest, 3}}))
      put_runtime(nil)

      assert get().js_input_paths == MapSet.new(["/app/runtime.mjs"])
    end

    test "marks the compile state as changed when a path joins" do
      dump_path = Path.join([Reflection.tmp_dir(), "tests", "compiler", "cache", "js_inputs.bin"])
      put_runtime(runtime_state_reading(%{}))
      dump_compile_state(dump_path, false)

      put_runtime(runtime_state_reading(%{"/app/runtime.mjs" => {:digest, 3}}))

      assert get().compile_state_changed?
    end

    test "is emptied by forget_bundles/0" do
      put_page(Module1, page_state_reading(%{"/app/a.mjs" => {:digest, 1}}), [])

      forget_bundles()

      assert get().js_input_paths == MapSet.new()
    end

    test "is kept by clear_module_infos/0" do
      put_page(Module1, page_state_reading(%{"/app/a.mjs" => {:digest, 1}}), [])

      clear_module_infos()

      assert get().js_input_paths == MapSet.new(["/app/a.mjs"])
    end

    test "is emptied by reset/0" do
      put_page(Module1, page_state_reading(%{"/app/a.mjs" => {:digest, 1}}), [])

      reset()

      assert get().js_input_paths == MapSet.new()
    end
  end

  describe "load_compile_state/1" do
    setup do
      dump_dir =
        Path.join([Reflection.tmp_dir(), "tests", "compiler", "cache", "load_compile_state_1"])

      clean_dir(dump_dir)

      [path: Path.join(dump_dir, "compile_state.bin")]
    end

    test "loads what dump_compile_state/2 wrote", %{path: path} do
      put_full_state()
      dump_compile_state(path, false)
      stop_cache()

      assert load_compile_state(path) == :ok

      assert %{
               app_versions: [hologram: "1.0.0"],
               bundle_inputs: %{client_stacktraces?: true},
               encoding_inputs: %{async_mfas: async_mfas, client_stacktraces?: true},
               js_input_paths: js_input_paths,
               module_metadata: %{Module1 => %{app: :hologram, file: "lib/module_1.ex"}},
               pages_plt: pages_plt,
               pending_pages: pending_pages,
               runtime: %{
                 app_versions: [hologram: "1.0.0"],
                 bundle_info: %{
                   digest: "b",
                   js_inputs: %{"/app/assets/js/runtime.mjs" => {:digest, 2}}
                 },
                 js_binding_modules: js_binding_modules,
                 mfas: [{Module1, :fun_1, 0}]
               },
               template_modules: template_modules
             } = get()

      assert async_mfas == MapSet.new()

      assert js_input_paths ==
               MapSet.new(["/app/assets/js/page.mjs", "/app/assets/js/runtime.mjs"])

      assert js_binding_modules == MapSet.new()
      assert pending_pages == MapSet.new([Module2])
      assert template_modules == %{Module1 => MapSet.new()}

      assert PLT.get_all(pages_plt) == %{
               Module1 => %{
                 bundle_info: %{
                   digest: "a",
                   js_inputs: %{"/app/assets/js/page.mjs" => {:digest, 1}}
                 },
                 modules: MapSet.new([Module1])
               }
             }
    end

    test "loads no page MFA lists", %{path: path} do
      put_full_state()
      dump_compile_state(path, false)
      stop_cache()

      load_compile_state(path)

      assert PLT.keys(get().page_mfas_plt) == []
    end

    test "marks the loaded state as unchanged", %{path: path} do
      put_full_state()
      dump_compile_state(path, false)
      stop_cache()

      load_compile_state(path)

      refute get().compile_state_changed?
    end

    test "the next dump of an unchanged state writes nothing", %{path: path} do
      put_full_state()
      dump_compile_state(path, false)
      stop_cache()
      load_compile_state(path)

      assert dump_compile_state(path, false) == :unchanged
    end

    test "a dump of another version is not loaded", %{path: path} do
      File.write!(
        path,
        SerializationUtils.serialize({0, %{pending_pages: MapSet.new([Module2])}})
      )

      put_pending_pages([Module1])

      assert load_compile_state(path) == :error

      assert %{compile_state_changed?: true, pending_pages: pending_pages} = get()
      assert pending_pages == MapSet.new([Module1])
    end
  end

  test "put_bundle_inputs/1" do
    bundle_inputs = %{
      client_stacktraces?: true,
      hologram_modules: [{Module1, 123}],
      js_sources: [{"hologram.mjs", 456, 789}],
      package_json_digest: "a"
    }

    assert put_bundle_inputs(bundle_inputs) == :ok
    assert %{bundle_inputs: ^bundle_inputs} = get()
  end

  test "put_encoding_inputs/1" do
    encoding_inputs = %{
      async_mfas: MapSet.new([{Module1, :fun_1, 0}]),
      client_stacktraces?: false
    }

    assert put_encoding_inputs(encoding_inputs) == :ok
    assert %{encoding_inputs: ^encoding_inputs} = get()
  end

  test "put_module_infos/2" do
    editable_modules = MapSet.new([Module1])

    assert put_module_infos(123, editable_modules) == :ok
    assert %{dumped_at: 123, editable_modules: ^editable_modules} = get()
  end

  test "put_module_metadata/1" do
    module_metadata = %{Module1 => %{app: :hologram, file: "lib/module_1.ex"}}

    assert put_module_metadata(module_metadata) == :ok
    assert %{module_metadata: ^module_metadata} = get()

    put_module_metadata(nil)

    assert get().module_metadata == nil
  end

  test "put_page/3" do
    page_state = %{bundle_info: %{digest: "a", js_inputs: %{}}, modules: MapSet.new([Module1])}
    mfas = [{Module1, :fun_1, 0}]

    assert put_page(Module1, page_state, mfas) == :ok
    assert PLT.get(get().pages_plt, Module1) == {:ok, page_state}
    assert PLT.get(get().page_mfas_plt, Module1) == {:ok, mfas}
  end

  test "put_pending_pages/1" do
    put_pending_pages([Module1, Module2])

    assert put_pending_pages([Module3]) == :ok
    assert get().pending_pages == MapSet.new([Module3])
  end

  test "put_runtime/1" do
    runtime_state = %{
      app_versions: [hologram: "1.0.0"],
      bundle_info: %{digest: "a", js_inputs: %{}},
      js_binding_modules: MapSet.new([Module1]),
      mfas: [{Module1, :fun_1, 0}]
    }

    assert put_runtime(runtime_state) == :ok
    assert %{runtime: ^runtime_state} = get()
  end

  test "put_template_modules/1" do
    template_modules = %{Module1 => MapSet.new([Module2]), Module2 => MapSet.new()}

    assert put_template_modules(template_modules) == :ok
    assert %{template_modules: ^template_modules} = get()
  end

  describe "reset/0" do
    test "stops the kept call graph and starts an empty one" do
      old_call_graph = get().call_graph
      CallGraph.add_vertex(old_call_graph, {Module1, :fun_1, 0})

      assert reset() == :ok

      new_call_graph = get().call_graph

      refute Process.alive?(old_call_graph.pid)
      assert new_call_graph.pid != old_call_graph.pid
      assert CallGraph.vertices(new_call_graph) == []
    end

    test "stops the kept encode PLT and starts an empty one, and forgets the encoding inputs" do
      old_encode_plt = get().encode_plt
      PLT.put(old_encode_plt, {Module1, :fun_1, 0}, "js")
      put_encoding_inputs(%{async_mfas: MapSet.new(), client_stacktraces?: true})

      assert reset() == :ok

      %{encode_plt: new_encode_plt, encoding_inputs: encoding_inputs} = get()

      refute Process.alive?(old_encode_plt.pid)
      assert new_encode_plt.table_ref != old_encode_plt.table_ref
      assert PLT.keys(new_encode_plt) == []
      assert encoding_inputs == nil
    end

    test "stops the kept IR PLT and starts an empty one" do
      old_ir_plt = get().ir_plt
      PLT.put(old_ir_plt, Module1, :ir_1)

      assert reset() == :ok

      new_ir_plt = get().ir_plt

      refute Process.alive?(old_ir_plt.pid)
      assert new_ir_plt.table_ref != old_ir_plt.table_ref
      assert PLT.keys(new_ir_plt) == []
    end

    test "stops the kept module info PLT and starts an empty one, and forgets the dump time and the editable modules" do
      old_module_info_plt = get().module_info_plt
      PLT.put(old_module_info_plt, Module1, %{digest: "a"})
      put_module_infos(123, MapSet.new([Module1]))

      reset()

      %{dumped_at: dumped_at, editable_modules: editable_modules, module_info_plt: new_plt} =
        get()

      refute Process.alive?(old_module_info_plt.pid)
      assert new_plt.table_ref != old_module_info_plt.table_ref
      assert PLT.keys(new_plt) == []
      assert dumped_at == nil
      assert editable_modules == nil
    end

    test "forgets the pending pages" do
      put_pending_pages([Module1])

      reset()

      assert get().pending_pages == MapSet.new()
    end

    test "stops the kept page states and MFA lists and forgets the app versions, the module metadata, the runtime, the template modules and the bundle inputs, and marks the compile state as unchanged" do
      %{page_mfas_plt: old_page_mfas_plt, pages_plt: old_pages_plt} = get()
      put_app_versions(hologram: "1.0.0")
      put_bundle_inputs(%{client_stacktraces?: true})
      put_module_metadata(%{Module1 => %{app: :hologram, file: "lib/module_1.ex"}})
      put_template_modules(%{Module1 => MapSet.new()})
      put_page(Module1, %{bundle_info: %{digest: "a", js_inputs: %{}}, modules: MapSet.new()}, [])

      put_runtime(%{
        app_versions: [],
        bundle_info: %{js_inputs: %{}},
        js_binding_modules: MapSet.new(),
        mfas: []
      })

      reset()

      %{
        app_versions: app_versions,
        bundle_inputs: bundle_inputs,
        compile_state_changed?: compile_state_changed?,
        module_metadata: module_metadata,
        page_mfas_plt: new_page_mfas_plt,
        pages_plt: new_pages_plt,
        runtime: runtime,
        template_modules: template_modules
      } = get()

      refute Process.alive?(old_pages_plt.pid)
      refute Process.alive?(old_page_mfas_plt.pid)
      assert new_pages_plt.table_ref != old_pages_plt.table_ref
      assert new_page_mfas_plt.table_ref != old_page_mfas_plt.table_ref
      assert PLT.keys(new_pages_plt) == []
      assert PLT.keys(new_page_mfas_plt) == []
      assert app_versions == nil
      assert bundle_inputs == nil
      refute compile_state_changed?
      assert module_metadata == nil
      assert runtime == nil
      assert template_modules == nil
    end
  end

  test "terminate/2" do
    %{
      call_graph: call_graph,
      encode_plt: encode_plt,
      ir_plt: ir_plt,
      module_info_plt: module_info_plt,
      page_mfas_plt: page_mfas_plt,
      pages_plt: pages_plt
    } = get()

    GenServer.stop(Cache)

    refute Process.alive?(call_graph.pid)
    refute Process.alive?(encode_plt.pid)
    refute Process.alive?(ir_plt.pid)
    refute Process.alive?(module_info_plt.pid)
    refute Process.alive?(page_mfas_plt.pid)
    refute Process.alive?(pages_plt.pid)
    assert :ets.whereis(Tracer) == :undefined
  end
end
