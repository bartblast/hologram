defmodule Hologram.Compiler.Cache do
  @moduledoc false

  # Kept between two compiles in the same VM, so that a live-reload compile patches the IR PLT
  # with the module digests diff and builds only the IR it is missing, instead of rebuilding the
  # IR of every module. The module infos of the last finished compile are kept with it: they are
  # the picture the IR PLT was last brought in line with, so the next compile diffs against them
  # rather than against the dump on disk, which another VM sharing the build dir may have rewritten.
  # Started on first use and not linked to the caller, so it outlives the compile that started it.
  # A compile that finds no module infos here treats the dump on disk as the before picture and
  # fills the IR PLT with what it reads, so nothing depends on the cache for correctness.

  use GenServer

  alias Hologram.Commons.PLT

  @type t :: %{
          ir_plt: PLT.t(),
          module_infos: %{module => map} | nil,
          dumped_at: non_neg_integer | nil
        }

  @doc """
  Returns the kept IR PLT, and the module infos and module info dump time of the last finished
  compile (nil when no compile has finished in this VM). Starts the cache on first use.
  """
  @spec get() :: t
  def get do
    GenServer.call(server(), :get)
  end

  @impl GenServer
  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:put_module_infos, module_infos, dumped_at}, _from, state) do
    {:reply, :ok, %{state | module_infos: module_infos, dumped_at: dumped_at}}
  end

  def handle_call(:reset, _from, state) do
    PLT.stop(state.ir_plt)
    {:reply, :ok, initial_state()}
  end

  @impl GenServer
  def init(nil) do
    {:ok, initial_state()}
  end

  @doc """
  Keeps the module infos of a compile that finished, and the mtime of the module info dump it wrote
  (in posix seconds), as the before picture of the next compile.
  """
  @spec put_module_infos(%{module => map}, non_neg_integer) :: :ok
  def put_module_infos(module_infos, dumped_at) do
    GenServer.call(server(), {:put_module_infos, module_infos, dumped_at})
  end

  @doc """
  Replaces the kept IR PLT with an empty one and forgets the kept module infos, so the next compile
  starts as the first one in the VM does.
  """
  @spec reset() :: :ok
  def reset do
    GenServer.call(server(), :reset)
  end

  # The IR PLT's process is linked to the cache, but a normal stop does not take a linked process
  # down with it, so the IR PLT is stopped here.
  @impl GenServer
  def terminate(_reason, state) do
    PLT.stop(state.ir_plt)
  end

  # The PLT is started from within the cache process, so its process is linked to the cache,
  # not to whichever process ran the compile.
  defp initial_state do
    %{ir_plt: PLT.start(), module_infos: nil, dumped_at: nil}
  end

  defp server do
    case GenServer.start(__MODULE__, nil, name: __MODULE__) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end
end
