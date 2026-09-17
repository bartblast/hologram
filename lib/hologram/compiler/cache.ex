defmodule Hologram.Compiler.Cache do
  @moduledoc false

  # Kept between two compiles in the same VM, so that a live-reload compile patches the IR PLT
  # and the call graph with the module digests diff and builds only the IR it is missing,
  # instead of rebuilding the IR of every module and reloading the graph from its dump. The
  # module infos of the last finished compile are kept with them: they are the picture both were
  # last brought in line with, so the next compile diffs against them rather than against the
  # dump on disk, which another VM sharing the build dir may have rewritten. Started on first use
  # and not linked to the caller, so it outlives the compile that started it. A compile that finds
  # no module infos here starts from the build dir, so nothing depends on the cache for
  # correctness.

  use GenServer

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.CallGraph

  @type t :: %{
          call_graph: CallGraph.t(),
          ir_plt: PLT.t(),
          module_infos: %{module => map} | nil
        }

  @doc """
  Returns the kept call graph and IR PLT, and the module infos of the last finished compile (nil
  when no compile has finished in this VM). Starts the cache on first use.
  """
  @spec get() :: t
  def get do
    GenServer.call(server(), :get)
  end

  @impl GenServer
  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:put_module_infos, module_infos}, _from, state) do
    {:reply, :ok, %{state | module_infos: module_infos}}
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
  Keeps the module infos of a compile that finished, as the before picture of the next compile.
  """
  @spec put_module_infos(%{module => map}) :: :ok
  def put_module_infos(module_infos) do
    GenServer.call(server(), {:put_module_infos, module_infos})
  end

  @doc """
  Replaces the kept call graph and IR PLT with empty ones and forgets the kept module infos, so the
  next compile starts from the build dir, as the first one in the VM does.
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
    %{call_graph: CallGraph.start(), ir_plt: PLT.start(), module_infos: nil}
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
