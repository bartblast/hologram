defmodule Hologram.Compiler.Cache do
  @moduledoc false

  # Kept between two compiles in the same VM, so that a live-reload compile patches the IR PLT
  # and the call graph with the module digests diff and builds only the IR it is missing,
  # instead of rebuilding the IR of every module and reloading the graph from its dump. The
  # JavaScript of each function the pages reach is kept too, with what it was encoded against
  # besides its module's IR, so that a save encodes again only the functions of the modules it
  # edited. The module infos of the last finished compile are kept with them, in a PLT, with the
  # mtime of the dump that compile wrote and the modules whose beams a save can rewrite: they are
  # the picture both were brought in line with, so the next compile diffs against them rather than
  # against the dump on disk, which another VM sharing the build dir may have rewritten. What each
  # page and the runtime were built from is kept too, so that a compile rebuilds only the pages an
  # edit reaches, with the pages a compile set out to build and has not built yet, so that the next
  # compile rebuilds them whether or not its own edit reaches them. So are the modules each
  # page's and component's template uses, so that a compile validates only the templates its
  # edit can affect, and each module's stack trace metadata, so that a compile rebuilds only the
  # entries of the modules it changed. The inputs every bundle depends on besides its modules
  # (Hologram's own code and JavaScript, the esbuild version, the client stack traces setting) are
  # kept with the bundles, so that a compile whose inputs differ forgets them. Started on first use
  # and not linked to the caller, so it outlives the compile that started it. A compile that finds
  # the module infos untrusted here (no editable modules kept) starts from the build dir, so nothing
  # depends on the cache for correctness.
  # The cache also registers Hologram.Compiler.Tracer when it starts, and owns its table: the
  # modules the tracer records are only of use to a compile that has the kept state to apply them
  # to, so the two live and die together.

  use GenServer

  alias Hologram.Commons.PLT
  alias Hologram.Commons.SerializationUtils
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Tracer

  # Bumped when the compile state's shape changes: a dump of another version is not loaded.
  @dump_version 2

  @type compile_state :: %{
          app_versions: keyword(String.t()) | nil,
          bundle_inputs: map | nil,
          encoding_inputs: encoding_inputs | nil,
          js_import_digests: %{String.t() => integer} | nil,
          module_metadata: %{module => %{app: atom | nil, file: String.t()}} | nil,
          pages: %{module => page_state},
          pending_pages: MapSet.t(module),
          runtime: runtime_state | nil,
          template_modules: %{module => MapSet.t(module)} | nil
        }

  @type encoding_inputs :: %{async_mfas: MapSet.t(mfa), client_stacktraces?: boolean}

  @type page_state :: %{bundle_info: map, modules: MapSet.t(module)}

  @type runtime_state :: %{
          app_versions: keyword(String.t()),
          bundle_info: map,
          js_binding_modules: MapSet.t(module),
          mfas: [mfa]
        }

  @type t :: %{
          app_versions: keyword(String.t()) | nil,
          bundle_inputs: map | nil,
          call_graph: CallGraph.t(),
          compile_state_changed?: boolean,
          dumped_at: non_neg_integer | nil,
          editable_modules: MapSet.t(module) | nil,
          encode_plt: PLT.t(),
          encoding_inputs: encoding_inputs | nil,
          ir_plt: PLT.t(),
          js_import_digests: %{String.t() => integer} | nil,
          module_info_plt: PLT.t(),
          module_metadata: %{module => %{app: atom | nil, file: String.t()}} | nil,
          page_mfas_plt: PLT.t(),
          pages_plt: PLT.t(),
          pending_pages: MapSet.t(module),
          runtime: runtime_state | nil,
          template_modules: %{module => MapSet.t(module)} | nil
        }

  @doc """
  Forgets the dump time and the editable modules, which marks the kept module infos as untrusted,
  while keeping the module info PLT's entries, the IR PLT, the encode PLT, the encoding inputs, the
  module metadata, the template modules, the bundle inputs, the imported JavaScript digests, whether
  the compile state changed since it was last dumped or loaded, and the call graph, so that the next
  compile starts from the build dir. The compile task calls it before it changes the kept state in
  place: a compile that dies mid-way must not leave a half-patched graph or half-scanned infos that
  the next compile would trust.
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
  Writes the compile state to the given path: the page states, the pending pages, the runtime state,
  the app versions, the encoding inputs, the module metadata, the template modules, the bundle
  inputs and the imported JavaScript digests, which a compile in a new VM needs to keep this VM's
  bundles (the after picture of a compile, next to the before picture the call graph and module info
  dumps are). The page MFA lists are left out: they are read only after a change of the runtime's
  MFAs, and a page without one is rebuilt then. Skipped when nothing in it changed since it was last
  written or loaded, unless forced: the compile task forces it when the dumps on disk are not this
  VM's. A change is marked by the functions that change what it holds, and a put of the value
  already kept marks none, so a compile that changes nothing neither copies the page states out of
  their PLT nor writes. Returns `:written` or `:unchanged`.
  """
  @spec dump_compile_state(String.t(), boolean) :: :written | :unchanged
  def dump_compile_state(path, force?) do
    GenServer.call(server(), {:dump_compile_state, path, force?}, :infinity)
  end

  @doc """
  Forgets every kept bundle and what was derived for it: the page states and MFA lists, the pending
  pages, the runtime state, the template modules, the encoding inputs, the encoded functions and
  the imported JavaScript digests, which describe the sources of the kept bundles. The call graph,
  the IR PLT, the module infos, the module metadata, the app versions and the bundle inputs describe
  the modules, not the JavaScript made from them, and stay. The compile task calls it when the
  bundle inputs changed (see `put_bundle_inputs/1`): the kept bundles were made by another Hologram
  build, so every page and the runtime are built again, as on a fresh build dir. The PLTs are
  emptied in place, so their references stay valid.
  """
  @spec forget_bundles() :: :ok
  def forget_bundles do
    GenServer.call(server(), :forget_bundles)
  end

  @doc """
  Returns the kept call graph, IR PLT, encode PLT and page states, the encoding inputs, the pending
  pages, the application versions, the module info PLT of the last finished compile with the mtime
  of the module info dump it wrote and the modules whose beams a save can rewrite, what the runtime
  bundle was built from, the stack trace metadata of every module, the MFA list of each page (apart
  from the rest of its state, since only a relisting after a change of the runtime's MFAs reads it),
  the modules each template uses, the inputs the bundles were built with and the digests of the
  JavaScript they import (the dump time, the editable modules, the encoding inputs, the module
  metadata, the runtime state, the template modules, the bundle inputs and the imported JavaScript
  digests are nil when no compile has finished in this VM, and the module info PLT's entries are
  then not to be trusted), and whether the compile state changed since it was last dumped or loaded.
  Starts the cache on first use.
  """
  @spec get() :: t
  def get do
    GenServer.call(server(), :get)
  end

  @impl GenServer
  def handle_call(:clear_module_infos, _from, state) do
    {:reply, :ok, %{state | dumped_at: nil, editable_modules: nil}}
  end

  def handle_call({:delete_page, page_module}, _from, state) do
    PLT.delete(state.page_mfas_plt, page_module)
    PLT.delete(state.pages_plt, page_module)
    {:reply, :ok, %{state | compile_state_changed?: true}}
  end

  def handle_call({:delete_pending_pages, page_modules}, _from, state) do
    pending_pages = MapSet.difference(state.pending_pages, MapSet.new(page_modules))
    {:reply, :ok, put_dumped_field(state, :pending_pages, pending_pages)}
  end

  def handle_call({:dump_compile_state, path, force?}, _from, state) do
    if force? or state.compile_state_changed? do
      state
      |> build_compile_state()
      |> write_compile_state(path)

      {:reply, :written, %{state | compile_state_changed?: false}}
    else
      {:reply, :unchanged, state}
    end
  end

  def handle_call(:forget_bundles, _from, state) do
    PLT.reset(state.encode_plt)
    PLT.reset(state.page_mfas_plt)
    PLT.reset(state.pages_plt)

    new_state = %{
      state
      | compile_state_changed?: true,
        encoding_inputs: nil,
        js_import_digests: nil,
        pending_pages: MapSet.new(),
        runtime: nil,
        template_modules: nil
    }

    {:reply, :ok, new_state}
  end

  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:load_compile_state, path}, _from, state) do
    case path
         |> File.read!()
         |> SerializationUtils.deserialize(true) do
      {@dump_version, compile_state} ->
        PLT.put(state.pages_plt, Map.to_list(compile_state.pages))

        new_state = %{
          state
          | app_versions: compile_state.app_versions,
            bundle_inputs: compile_state.bundle_inputs,
            compile_state_changed?: false,
            encoding_inputs: compile_state.encoding_inputs,
            js_import_digests: compile_state.js_import_digests,
            module_metadata: compile_state.module_metadata,
            pending_pages: compile_state.pending_pages,
            runtime: compile_state.runtime,
            template_modules: compile_state.template_modules
        }

        {:reply, :ok, new_state}

      _other_version ->
        {:reply, :error, state}
    end
  end

  def handle_call({:put_app_versions, app_versions}, _from, state) do
    {:reply, :ok, put_dumped_field(state, :app_versions, app_versions)}
  end

  def handle_call({:put_bundle_inputs, bundle_inputs}, _from, state) do
    {:reply, :ok, put_dumped_field(state, :bundle_inputs, bundle_inputs)}
  end

  def handle_call({:put_encoding_inputs, encoding_inputs}, _from, state) do
    {:reply, :ok, put_dumped_field(state, :encoding_inputs, encoding_inputs)}
  end

  def handle_call({:put_js_import_digests, js_import_digests}, _from, state) do
    {:reply, :ok, put_dumped_field(state, :js_import_digests, js_import_digests)}
  end

  def handle_call({:put_module_infos, dumped_at, editable_modules}, _from, state) do
    {:reply, :ok, %{state | dumped_at: dumped_at, editable_modules: editable_modules}}
  end

  def handle_call({:put_module_metadata, module_metadata}, _from, state) do
    {:reply, :ok, put_dumped_field(state, :module_metadata, module_metadata)}
  end

  def handle_call({:put_page, page_module, page_state, mfas}, _from, state) do
    PLT.put(state.page_mfas_plt, page_module, mfas)
    PLT.put(state.pages_plt, page_module, page_state)
    {:reply, :ok, %{state | compile_state_changed?: true}}
  end

  def handle_call({:put_pending_pages, page_modules}, _from, state) do
    {:reply, :ok, put_dumped_field(state, :pending_pages, MapSet.new(page_modules))}
  end

  def handle_call({:put_runtime, runtime_state}, _from, state) do
    {:reply, :ok, put_dumped_field(state, :runtime, runtime_state)}
  end

  def handle_call({:put_template_modules, template_modules}, _from, state) do
    {:reply, :ok, put_dumped_field(state, :template_modules, template_modules)}
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
  Loads the compile state `dump_compile_state/2` wrote at the given path into the kept state: the
  page states into the pages PLT and the rest into their fields, and marks it as unchanged, so that
  a compile that changes none of it does not write it again. Returns `:error`
  without touching anything when the dump is of another version. The compile task calls it on the
  first compile in a VM, once the call graph dump has loaded: the page states are trusted only
  against the diff of the module infos that graph was brought in line with.
  """
  @spec load_compile_state(String.t()) :: :ok | :error
  def load_compile_state(path) do
    GenServer.call(server(), {:load_compile_state, path}, :infinity)
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
  Keeps what every bundle depends on besides the modules it carries, as
  `Hologram.Compiler.build_bundle_inputs/2` computes it: the Hologram code and JavaScript, the
  esbuild version and the client stack traces setting the kept bundles were built with. The next
  compile keeps its bundles only while its own inputs are equal to these.
  """
  @spec put_bundle_inputs(map) :: :ok
  def put_bundle_inputs(bundle_inputs) do
    GenServer.call(server(), {:put_bundle_inputs, bundle_inputs})
  end

  @doc """
  Keeps what the kept function encodings depend on besides their modules' IR: the async MFAs, which
  decide what a function awaits and whether it is awaited, and the client stacktraces setting. The
  next compile keeps the encodings only while its own inputs are equal to these.
  """
  @spec put_encoding_inputs(encoding_inputs) :: :ok
  def put_encoding_inputs(encoding_inputs) do
    GenServer.call(server(), {:put_encoding_inputs, encoding_inputs})
  end

  @doc """
  Keeps the digest of each JavaScript source the modules declaring `js_import` name, as
  `Hologram.Compiler.build_js_import_digests/1` computes them. A bundle inlines those sources and no
  beam moves when one is edited, so the next compile compares its own digests with these to find the
  importers whose bundles must be rebuilt (see `Hologram.Compiler.list_changed_js_importers/3`).
  """
  @spec put_js_import_digests(%{String.t() => integer}) :: :ok
  def put_js_import_digests(js_import_digests) do
    GenServer.call(server(), {:put_js_import_digests, js_import_digests})
  end

  @doc """
  Marks the entries of the kept module info PLT, which the compile has put there, as the module infos
  of a compile that finished, with the mtime in posix seconds of the module info dump it wrote: the
  before picture of the next compile. The two are kept together because the reuse guard of
  `Hologram.Compiler.build_module_info_plt!/3` compares the entries against that mtime: a time read
  from the dump on disk can belong to a later compile by another VM, and would make the guard trust
  an entry it should re-read.

  With them go the modules whose beams a save can rewrite, as
  `Hologram.Reflection.list_editable_beams/0` listed them at that compile: the next compile rescans
  those and what the same directories hold then, and leaves every other entry as it is (see
  `Hologram.Compiler.patch_module_info_plt!/5`). Kept with the infos because a module among them
  that has no beam any more was removed, which the infos alone cannot tell from a dependency's
  module.
  """
  @spec put_module_infos(non_neg_integer, MapSet.t(module)) :: :ok
  def put_module_infos(dumped_at, editable_modules) do
    GenServer.call(server(), {:put_module_infos, dumped_at, editable_modules})
  end

  @doc """
  Keeps the stack trace metadata of every module, as `Hologram.Compiler.build_module_metadata/1`
  builds it, so that a compile builds again only the entries of the modules its edit touched. nil
  when client stack traces are off, since the bundles register no metadata then.
  """
  @spec put_module_metadata(%{module => %{app: atom | nil, file: String.t()}} | nil) :: :ok
  def put_module_metadata(module_metadata) do
    GenServer.call(server(), {:put_module_metadata, module_metadata})
  end

  @doc """
  Keeps the modules a page reaches and the info of the bundle built from them, so that the next
  compile can reuse that bundle when nothing the page reaches has changed, and the page's reachable
  MFAs in a PLT of their own, which the page partition reads only when the runtime's MFAs changed:
  the per-compile partition copies the state of every page, and the MFAs are the bulk of it. Put
  right after the bundle is written, so the state and the file on disk go together.
  """
  @spec put_page(module, page_state, [mfa]) :: :ok
  def put_page(page_module, page_state, mfas) do
    GenServer.call(server(), {:put_page, page_module, page_state, mfas})
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
  every page bundle leaves out), the application versions it carries and the info of its bundle. nil
  forgets it, so that the next compile rebuilds the runtime bundle.
  """
  @spec put_runtime(runtime_state | nil) :: :ok
  def put_runtime(runtime_state) do
    GenServer.call(server(), {:put_runtime, runtime_state})
  end

  @doc """
  Keeps, for each page and component, the modules its template uses as components, as
  `Hologram.Compiler.validate_prop_usages/2` returns them, so that a compile validates only the
  templates its edit can affect (see `Hologram.Compiler.list_templatables_to_validate/3`).
  """
  @spec put_template_modules(%{module => MapSet.t(module)}) :: :ok
  def put_template_modules(template_modules) do
    GenServer.call(server(), {:put_template_modules, template_modules})
  end

  @doc """
  Replaces the kept call graph, module info PLT, IR PLT, encode PLT, page states and page MFA lists
  with empty ones
  and forgets the kept dump time, editable modules, encoding inputs, module metadata, pending pages,
  application versions, runtime state, template modules, bundle inputs and imported JavaScript
  digests, and marks the compile state as unchanged, so the next compile starts from the build dir,
  as the first one in the VM does.
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

  defp build_compile_state(state) do
    %{
      app_versions: state.app_versions,
      bundle_inputs: state.bundle_inputs,
      encoding_inputs: state.encoding_inputs,
      js_import_digests: state.js_import_digests,
      module_metadata: state.module_metadata,
      pages: PLT.get_all(state.pages_plt),
      pending_pages: state.pending_pages,
      runtime: state.runtime,
      template_modules: state.template_modules
    }
  end

  # The call graph and the PLTs are started from within the cache process, so their processes are
  # linked to the cache, not to whichever process ran the compile.
  defp initial_state do
    %{
      app_versions: nil,
      bundle_inputs: nil,
      call_graph: CallGraph.start(),
      compile_state_changed?: false,
      dumped_at: nil,
      editable_modules: nil,
      encode_plt: PLT.start(),
      encoding_inputs: nil,
      ir_plt: PLT.start(),
      js_import_digests: nil,
      module_info_plt: PLT.start(),
      module_metadata: nil,
      page_mfas_plt: PLT.start(),
      pages_plt: PLT.start(),
      pending_pages: MapSet.new(),
      runtime: nil,
      template_modules: nil
    }
  end

  # Sets a field the compile state dump holds, and marks the compile state as changed when the value
  # differs from the kept one: the compile task puts most of them again on every compile, and a
  # compile that changed nothing must not rewrite the dump.
  defp put_dumped_field(state, key, value) do
    if Map.fetch!(state, key) == value do
      state
    else
      %{state | key => value, :compile_state_changed? => true}
    end
  end

  defp server do
    case GenServer.start(__MODULE__, nil, name: __MODULE__) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end

  defp stop_kept(state) do
    CallGraph.stop(state.call_graph)
    PLT.stop(state.encode_plt)
    PLT.stop(state.ir_plt)
    PLT.stop(state.module_info_plt)
    PLT.stop(state.page_mfas_plt)
    PLT.stop(state.pages_plt)
  end

  # Its own function, so that the compile task's tests can count the writes.
  defp write_compile_state(compile_state, path) do
    data = SerializationUtils.serialize({@dump_version, compile_state})

    path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(path, data)
  end
end
