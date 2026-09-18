defmodule Hologram.Compiler.Cache do
  @moduledoc false

  # Kept between two compiles in the same VM, so that a live-reload compile patches the IR PLT
  # and the call graph with the module digests diff and builds only the IR it is missing,
  # instead of rebuilding the IR of every module and reloading the graph from its dump. The
  # module infos of the last finished compile are kept with them, with the mtime of the dump that
  # compile wrote and the modules whose beams a save can rewrite: they are the picture both were
  # brought in line with, so the next compile diffs against them rather than against the dump on
  # disk, which another VM sharing the build dir may have rewritten. What each page and the
  # runtime were built from is kept too, so that a compile rebuilds only the pages an edit
  # reaches, with the pages a compile set out to build and has not built yet, so that the next
  # compile rebuilds them whether or not its own edit reaches them. Started on first use and not
  # linked to the caller, so it outlives the compile that started it. A compile that finds no
  # module infos here starts from the build dir, so nothing depends on the cache for correctness.
  # The cache also registers Hologram.Compiler.Tracer when it starts, and owns its table: the
  # modules the tracer records are only of use to a compile that has the kept state to apply them
  # to, so the two live and die together.

  use GenServer

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Tracer

  @type page_state :: %{mfas: [mfa], modules: MapSet.t(module), bundle_info: map}

  @type runtime_state :: %{
          app_versions: keyword(String.t()),
          bundle_info: map,
          js_binding_modules: MapSet.t(module),
          mfas: [mfa]
        }

  @type t :: %{
          app_versions: keyword(String.t()) | nil,
          call_graph: CallGraph.t(),
          dumped_at: non_neg_integer | nil,
          editable_modules: MapSet.t(module) | nil,
          ir_plt: PLT.t(),
          module_infos: %{module => map} | nil,
          pages_plt: PLT.t(),
          pending_pages: MapSet.t(module),
          runtime: runtime_state | nil
        }

  @doc """
  Forgets the kept module infos, dump time and editable modules while keeping the IR PLT and the call
  graph, so that the next compile starts from the build dir. The compile task calls it before it changes
  the kept state in place: a compile that dies mid-way must not leave a half-patched graph that the next
  compile would trust.
  """
  @spec clear_module_infos() :: :ok
  def clear_module_infos do
    GenServer.call(server(), :clear_module_infos)
  end

  @doc """
  Forgets what a page was built from, for a page that no longer exists.
  """
  @spec delete_page(module) :: :ok
  def delete_page(page_module) do
    GenServer.call(server(), {:delete_page, page_module})
  end

  @doc """
  Forgets the given pages as pending. The compile task calls it once it has built their bundles.
  """
  @spec delete_pending_pages([module]) :: :ok
  def delete_pending_pages(page_modules) do
    GenServer.call(server(), {:delete_pending_pages, page_modules})
  end

  @doc """
  Returns the kept call graph, IR PLT and page states, the pending pages, the application versions, the module infos of
  the last finished compile with the mtime of the module info dump it wrote and the modules whose
  beams a save can rewrite, and what the runtime bundle was built from (the module infos, the
  editable modules and the runtime state are nil when no compile has finished in this VM). Starts
  the cache on first use.
  """
  @spec get() :: t
  def get do
    GenServer.call(server(), :get)
  end

  @impl GenServer
  def handle_call(:clear_module_infos, _from, state) do
    {:reply, :ok, %{state | dumped_at: nil, editable_modules: nil, module_infos: nil}}
  end

  def handle_call({:delete_page, page_module}, _from, state) do
    PLT.delete(state.pages_plt, page_module)
    {:reply, :ok, state}
  end

  def handle_call({:delete_pending_pages, page_modules}, _from, state) do
    pending_pages = MapSet.difference(state.pending_pages, MapSet.new(page_modules))
    {:reply, :ok, %{state | pending_pages: pending_pages}}
  end

  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:put_app_versions, app_versions}, _from, state) do
    {:reply, :ok, %{state | app_versions: app_versions}}
  end

  def handle_call({:put_module_infos, module_infos, dumped_at, editable_modules}, _from, state) do
    {:reply, :ok,
     %{
       state
       | dumped_at: dumped_at,
         editable_modules: editable_modules,
         module_infos: module_infos
     }}
  end

  def handle_call({:put_page, page_module, page_state}, _from, state) do
    PLT.put(state.pages_plt, page_module, page_state)
    {:reply, :ok, state}
  end

  def handle_call({:put_pending_pages, page_modules}, _from, state) do
    {:reply, :ok, %{state | pending_pages: MapSet.new(page_modules)}}
  end

  def handle_call({:put_runtime, runtime_state}, _from, state) do
    {:reply, :ok, %{state | runtime: runtime_state}}
  end

  def handle_call(:reset, _from, state) do
    stop_kept(state)
    {:reply, :ok, initial_state()}
  end

  @impl GenServer
  def init(nil) do
    # Before the first compile in the VM scans, so that every module compiled after it is recorded.
    Tracer.register()

    {:ok, initial_state()}
  end

  @doc """
  Keeps the version of each application the call graph reaches, as `Hologram.Compiler.build_app_versions/1`
  computes them, so that a compile whose edit cannot have changed them does not compute them again (see
  `Hologram.Compiler.app_versions_changed?/2`).
  """
  @spec put_app_versions(keyword(String.t())) :: :ok
  def put_app_versions(app_versions) do
    GenServer.call(server(), {:put_app_versions, app_versions})
  end

  @doc """
  Keeps the module infos of a compile that finished, and the mtime in posix seconds of the module info
  dump it wrote, as the before picture of the next compile. The two are kept together because the reuse
  guard of `Hologram.Compiler.build_module_info_plt!/3` compares the entries against that mtime: a time
  read from the dump on disk can belong to a later compile by another VM, and would make the guard
  trust an entry it should re-read.

  With them go the modules whose beams a save can rewrite, as `Hologram.Reflection.list_editable_beams/0`
  listed them at that compile: the next compile rescans those and what the same directories hold then,
  and copies every other entry (see `Hologram.Compiler.update_module_info_plt!/5`). Kept with the infos
  because a module among them that has no beam any more was removed, which the infos alone cannot tell
  from a dependency's module.
  """
  @spec put_module_infos(%{module => map}, non_neg_integer, MapSet.t(module)) :: :ok
  def put_module_infos(module_infos, dumped_at, editable_modules) do
    GenServer.call(server(), {:put_module_infos, module_infos, dumped_at, editable_modules})
  end

  @doc """
  Keeps a page's reachable MFAs, their modules and the info of the bundle built from them, so that the
  next compile can reuse that bundle when nothing the page reaches has changed. Put right after the
  bundle is written, so the state and the file on disk go together.
  """
  @spec put_page(module, page_state) :: :ok
  def put_page(page_module, page_state) do
    GenServer.call(server(), {:put_page, page_module, page_state})
  end

  @doc """
  Keeps the pages a compile is about to build, in place of the ones kept before, so that whatever it
  leaves unbuilt (a scheduler that stops the compile before their batch, or a failure) is rebuilt by
  the next compile.
  """
  @spec put_pending_pages([module]) :: :ok
  def put_pending_pages(page_modules) do
    GenServer.call(server(), {:put_pending_pages, page_modules})
  end

  @doc """
  Keeps what the runtime bundle was built from: its MFAs, the JS import modules it registers (which
  every page bundle leaves out), the application versions it carries and the info of its bundle.
  """
  @spec put_runtime(runtime_state) :: :ok
  def put_runtime(runtime_state) do
    GenServer.call(server(), {:put_runtime, runtime_state})
  end

  @doc """
  Replaces the kept call graph, IR PLT and page states with empty ones and forgets the kept module
  infos, dump time, editable modules, pending pages, application versions and runtime state, so the
  next compile starts from the build dir, as the first one in the VM does.
  """
  @spec reset() :: :ok
  def reset do
    GenServer.call(server(), :reset)
  end

  # The call graph's and the PLTs' processes are linked to the cache, but a normal stop does
  # not take a linked process down with it, so they are stopped here.
  @impl GenServer
  def terminate(_reason, state) do
    stop_kept(state)
  end

  # The call graph and the PLTs are started from within the cache process, so their processes are
  # linked to the cache, not to whichever process ran the compile.
  defp initial_state do
    %{
      app_versions: nil,
      call_graph: CallGraph.start(),
      dumped_at: nil,
      editable_modules: nil,
      ir_plt: PLT.start(),
      module_infos: nil,
      pages_plt: PLT.start(),
      pending_pages: MapSet.new(),
      runtime: nil
    }
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
    PLT.stop(state.pages_plt)
  end
end
