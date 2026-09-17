defmodule Hologram.Compiler.Cache do
  @moduledoc false

  # Kept between two compiles in the same VM, so that a live-reload compile patches the IR PLT
  # and the call graph with the module digests diff and builds only the IR it is missing,
  # instead of rebuilding the IR of every module and reloading the graph from its dump. The
  # module infos of the last finished compile are kept with them, with the mtime of the dump that
  # compile wrote: they are the picture both were brought in line with, so the next compile diffs
  # against them rather than against the dump on disk, which another VM sharing the build dir may
  # have rewritten. Started on first use
  # and not linked to the caller, so it outlives the compile that started it. A compile that finds
  # no module infos here starts from the build dir, so nothing depends on the cache for
  # correctness.

  use GenServer

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.CallGraph

  @type t :: %{
          call_graph: CallGraph.t(),
          dumped_at: non_neg_integer | nil,
          ir_plt: PLT.t(),
          module_infos: %{module => map} | nil
        }

  @doc """
  Forgets the kept module infos and dump time while keeping the IR PLT and the call graph, so that the
  next compile starts from the build dir. The compile task calls it before it changes the kept state in
  place: a compile that dies mid-way must not leave a half-patched graph that the next compile would
  trust.
  """
  @spec clear_module_infos() :: :ok
  def clear_module_infos do
    GenServer.call(server(), :clear_module_infos)
  end

  @doc """
  Returns the kept call graph and IR PLT, and the module infos of the last finished compile with the
  mtime of the module info dump it wrote (both nil when no compile has finished in this VM). Starts
  the cache on first use.
  """
  @spec get() :: t
  def get do
    GenServer.call(server(), :get)
  end

  @impl GenServer
  def handle_call(:clear_module_infos, _from, state) do
    {:reply, :ok, %{state | dumped_at: nil, module_infos: nil}}
  end

  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:put_module_infos, module_infos, dumped_at}, _from, state) do
    {:reply, :ok, %{state | dumped_at: dumped_at, module_infos: module_infos}}
  end

  def handle_call(:reset, _from, state) do
    stop_kept(state)
    {:reply, :ok, initial_state()}
  end

  @impl GenServer
  def init(nil) do
    {:ok, initial_state()}
  end

  @doc """
  Keeps the module infos of a compile that finished, and the mtime in posix seconds of the module info
  dump it wrote, as the before picture of the next compile. The two are kept together because the reuse
  guard of `Hologram.Compiler.build_module_info_plt!/3` compares the entries against that mtime: a time
  read from the dump on disk can belong to a later compile by another VM, and would make the guard
  trust an entry it should re-read.
  """
  @spec put_module_infos(%{module => map}, non_neg_integer) :: :ok
  def put_module_infos(module_infos, dumped_at) do
    GenServer.call(server(), {:put_module_infos, module_infos, dumped_at})
  end

  @doc """
  Replaces the kept call graph and IR PLT with empty ones and forgets the kept module infos and dump
  time, so the next compile starts from the build dir, as the first one in the VM does.
  """
  @spec reset() :: :ok
  def reset do
    GenServer.call(server(), :reset)
  end

  # The call graph's and the IR PLT's processes are linked to the cache, but a normal stop does
  # not take a linked process down with it, so they are stopped here.
  @impl GenServer
  def terminate(_reason, state) do
    stop_kept(state)
  end

  # The call graph and the PLT are started from within the cache process, so their processes are
  # linked to the cache, not to whichever process ran the compile.
  defp initial_state do
    %{call_graph: CallGraph.start(), dumped_at: nil, ir_plt: PLT.start(), module_infos: nil}
  end

  defp server do
    case GenServer.start(__MODULE__, nil, name: __MODULE__) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end

  defp stop_kept(state) do
    CallGraph.stop(state.call_graph)
    PLT.stop(state.ir_plt)
  end
end
