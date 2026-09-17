defmodule Hologram.Compiler.CacheTest do
  use Hologram.Test.BasicCase, async: false
  import Hologram.Compiler.Cache

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.Cache

  setup do
    stop_cache()
    on_exit(&stop_cache/0)
  end

  defp stop_cache do
    if Process.whereis(Cache), do: GenServer.stop(Cache)
  end

  describe "get/0" do
    test "starts the cache on first use" do
      refute Process.whereis(Cache)

      get()

      assert is_pid(Process.whereis(Cache))
    end

    test "returns an empty IR PLT and no module infos at first" do
      assert %{ir_plt: %PLT{} = ir_plt, module_infos: nil, dumped_at: nil} = get()
      assert PLT.keys(ir_plt) == []
    end

    test "returns the same IR PLT on every call" do
      assert get().ir_plt == get().ir_plt
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
    assert %{module_infos: ^module_infos, dumped_at: 123} = get()
  end

  describe "reset/0" do
    test "stops the kept IR PLT and starts an empty one" do
      old_ir_plt = get().ir_plt
      PLT.put(old_ir_plt, Module1, :ir_1)

      assert reset() == :ok

      new_ir_plt = get().ir_plt

      refute Process.alive?(old_ir_plt.pid)
      assert new_ir_plt.table_ref != old_ir_plt.table_ref
      assert PLT.keys(new_ir_plt) == []
    end

    test "forgets the module infos" do
      put_module_infos(%{Module1 => %{digest: "a"}}, 123)

      reset()

      assert %{module_infos: nil, dumped_at: nil} = get()
    end
  end

  test "terminate/2" do
    ir_plt = get().ir_plt

    GenServer.stop(Cache)

    refute Process.alive?(ir_plt.pid)
  end
end
