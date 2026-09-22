defmodule Hologram.Compiler.CacheTest do
  use Hologram.Test.BasicCase, async: false
  import Hologram.Compiler.Cache

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.Cache
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Tracer

  setup do
    stop_cache()
    on_exit(&stop_cache/0)
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
  end

  describe "delete_page/2" do
    test "forgets a kept page" do
      put_page(Module1, %{bundle_info: %{digest: "a"}, modules: MapSet.new()}, [])

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
               call_graph: %CallGraph{} = call_graph,
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
    page_state = %{bundle_info: %{digest: "a"}, modules: MapSet.new([Module1])}
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
      bundle_info: %{digest: "a"},
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

    test "stops the kept page states and MFA lists and forgets the app versions, the module metadata, the runtime and the template modules" do
      %{page_mfas_plt: old_page_mfas_plt, pages_plt: old_pages_plt} = get()
      put_app_versions(hologram: "1.0.0")
      put_module_metadata(%{Module1 => %{app: :hologram, file: "lib/module_1.ex"}})
      put_template_modules(%{Module1 => MapSet.new()})
      put_page(Module1, %{bundle_info: %{digest: "a"}, modules: MapSet.new()}, [])

      put_runtime(%{
        app_versions: [],
        bundle_info: %{},
        js_binding_modules: MapSet.new(),
        mfas: []
      })

      reset()

      %{
        app_versions: app_versions,
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
