defmodule Hologram.Compiler.CacheTest do
  use Hologram.Test.BasicCase, async: false
  import Hologram.Compiler.Cache

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.Cache
  alias Hologram.Compiler.CallGraph

  setup do
    stop_cache()
    on_exit(&stop_cache/0)
  end

  defp stop_cache do
    if Process.whereis(Cache), do: GenServer.stop(Cache)
  end

  describe "clear_module_infos/0" do
    test "forgets the module infos and the dump time" do
      put_module_infos(%{Module1 => %{digest: "a"}}, 123)

      assert clear_module_infos() == :ok
      assert %{dumped_at: nil, module_infos: nil} = get()
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
  end

  describe "delete_page/2" do
    test "forgets a kept page" do
      put_page(Module1, %{mfas: [], modules: MapSet.new(), bundle_info: %{digest: "a"}})

      assert delete_page(Module1) == :ok
      assert PLT.get(get().pages_plt, Module1) == :error
    end

    test "a page that was never kept" do
      assert delete_page(Module1) == :ok
    end
  end

  describe "get/0" do
    test "starts the cache on first use" do
      refute Process.whereis(Cache)

      get()

      assert is_pid(Process.whereis(Cache))
    end

    test "returns empty kept state at first" do
      assert %{
               call_graph: %CallGraph{} = call_graph,
               dumped_at: nil,
               ir_plt: %PLT{} = ir_plt,
               module_infos: nil,
               pages_plt: %PLT{} = pages_plt,
               runtime: nil
             } = get()

      assert CallGraph.vertices(call_graph) == []
      assert PLT.keys(ir_plt) == []
      assert PLT.keys(pages_plt) == []
    end

    test "returns the same call graph and PLTs on every call" do
      %{call_graph: call_graph, ir_plt: ir_plt, pages_plt: pages_plt} = get()

      assert %{call_graph: ^call_graph, ir_plt: ^ir_plt, pages_plt: ^pages_plt} = get()
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

  test "put_module_infos/2" do
    module_infos = %{Module1 => %{digest: "a"}}

    assert put_module_infos(module_infos, 123) == :ok
    assert %{dumped_at: 123, module_infos: ^module_infos} = get()
  end

  test "put_page/2" do
    page_state = %{
      mfas: [{Module1, :fun_1, 0}],
      modules: MapSet.new([Module1]),
      bundle_info: %{digest: "a"}
    }

    assert put_page(Module1, page_state) == :ok
    assert PLT.get(get().pages_plt, Module1) == {:ok, page_state}
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

    test "stops the kept IR PLT and starts an empty one" do
      old_ir_plt = get().ir_plt
      PLT.put(old_ir_plt, Module1, :ir_1)

      assert reset() == :ok

      new_ir_plt = get().ir_plt

      refute Process.alive?(old_ir_plt.pid)
      assert new_ir_plt.table_ref != old_ir_plt.table_ref
      assert PLT.keys(new_ir_plt) == []
    end

    test "forgets the module infos and the dump time" do
      put_module_infos(%{Module1 => %{digest: "a"}}, 123)

      reset()

      assert %{dumped_at: nil, module_infos: nil} = get()
    end

    test "stops the kept page states and starts an empty PLT" do
      old_pages_plt = get().pages_plt
      put_page(Module1, %{mfas: [], modules: MapSet.new(), bundle_info: %{digest: "a"}})

      put_runtime(%{
        app_versions: [],
        bundle_info: %{},
        js_binding_modules: MapSet.new(),
        mfas: []
      })

      reset()

      %{pages_plt: new_pages_plt, runtime: runtime} = get()

      refute Process.alive?(old_pages_plt.pid)
      assert new_pages_plt.table_ref != old_pages_plt.table_ref
      assert PLT.keys(new_pages_plt) == []
      assert runtime == nil
    end
  end

  test "terminate/2" do
    %{call_graph: call_graph, ir_plt: ir_plt, pages_plt: pages_plt} = get()

    GenServer.stop(Cache)

    refute Process.alive?(call_graph.pid)
    refute Process.alive?(ir_plt.pid)
    refute Process.alive?(pages_plt.pid)
  end
end
