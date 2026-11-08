defmodule Hologram.LiveReload do
  @moduledoc false

  use GenServer

  require Logger

  alias Hologram.Assets.ChunkRegistry
  alias Hologram.Assets.ManifestCache
  alias Hologram.Assets.PageDigestRegistry
  alias Hologram.Assets.PathRegistry
  alias Hologram.LiveReload.Diagnostic
  alias Hologram.Realtime.SubscriptionRegistry
  alias Hologram.Reflection
  alias Hologram.Router.PageModuleResolver

  @doc """
  Reloads the application after a change of the given file (nil when a request for a pending page
  starts the pass), using the given endpoint. The options go to the Hologram compile task:
  `:next_batch` and `:bundles_built` (see `Mix.Tasks.Compile.Hologram`). Returns `:ok` when the
  code compiled, and the error as lines of toned segments (see `Hologram.LiveReload.Diagnostic`)
  when the Elixir compile or the Hologram compile refused it.
  """
  @callback reload(String.t() | nil, any, keyword) :: :ok | {:error, [[Diagnostic.segment()]]}

  # How long a request for a pending page waits for its bundle, in milliseconds. Past it the page is
  # served with the bundle it had, and the reload event heals the tab once the page is built.
  @await_page_timeout 60_000

  # How long a tab may be seen without an SSE connection before it counts as closed, in
  # milliseconds. A tab is without one between its page's render and the stream's attach, which
  # SubscriptionRegistry.attach_wait_ms/0 bounds, and while it reconnects, each attempt up to the
  # client's 5 s backoff ceiling. Six attach windows cover the first and a few of the second.
  @connection_grace_ms 6 * SubscriptionRegistry.attach_wait_ms()

  # in milliseconds
  @debounce_delay 1_000

  # How long asset changes are gathered before the tabs are told, in milliseconds. A tool that
  # rebuilds the app's assets writes several files at once, and they make one change.
  @asset_debounce_delay 100

  # The asset types whose change in the app's priv/static dir the tabs are told about, the ones
  # Phoenix's default live reload patterns list.
  @asset_extensions ~w(.css .js .png .jpeg .jpg .gif .svg)

  # The file events that tell a dir was created, removed or renamed, as the watcher's backends name
  # them on each OS.
  @dir_change_events ~w(created deleted moved_from moved_to removed renamed)a

  # The priv/static subdirs whose files are not the app's assets: the dir Hologram's bundles went to
  # before they moved to Hologram's build dir, which the first compile after the move removes, and
  # files users upload, as in Phoenix's default live reload patterns.
  @ignored_static_subdirs ~w(hologram uploads)

  @doc """
  Starts live reload process, registered under its module name.

  ## Options

    * `:watch?` - whether to watch the source files and the app's static dir (default: `true`).
      Tests start the process without watching anything.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(opts) do
    if Keyword.get(opts, :watch?, true) do
      {:ok, pid} =
        :os.type()
        |> watcher_opts()
        |> FileSystem.start_link()

      FileSystem.subscribe(pid)
    end

    {:ok, initial_state(Reflection.phoenix_endpoint())}
  end

  @impl GenServer
  def handle_call({:await_page, page_module}, from, state) do
    if MapSet.member?(state.pending, page_module) do
      # Kept in request order, which is the order they are built in. A handful of pages at most.
      priority =
        if page_module in state.priority,
          do: state.priority,
          # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
          else: state.priority ++ [page_module]

      waiters = Map.update(state.waiters, page_module, [from], &[from | &1])
      new_state = %{state | priority: priority, waiters: waiters}

      # With no pass running, the page is pending because the last one failed before building it:
      # a new pass builds it, first. Its compile finds nothing to recompile but the pages left
      # pending.
      if new_state.pass do
        {:noreply, new_state}
      else
        {:noreply, start_pass(nil, new_state)}
      end
    else
      {:reply, :ok, state}
    end
  end

  def handle_call({:bundles_built, built}, _from, state) do
    pages = built -- [:chunks, :runtime]

    # The first batch of a pass is where the registries learn what the compile wrote: the pages and
    # routes of the module info dump, the static files, among them a new runtime bundle and new
    # chunk bundles, the chunks each struct type needs and each page preloads, and the page
    # digests. Later batches change the page digests and the chunks their pages preload only.
    if state.pass.registries_reloaded? do
      ChunkRegistry.reload()
      PageDigestRegistry.reload()
    else
      reload_runtime()
    end

    # A rebuilt runtime bundle no longer matches the page bundles any tab holds, so every tab
    # reloads, the ones on pages this pass has not built yet included: they ask for their page,
    # which is then built next. Rebuilt chunks reload every tab too: a tab that loaded a chunk
    # holds its old code, and no page bundle carries the implementation that changed, so only a
    # reload brings the new code in.
    if :runtime in built or :chunks in built do
      broadcast_reload(:all)
    else
      broadcast_reload(pages)
    end

    {released_waiters, waiters} = Map.split(state.waiters, pages)
    reply_to_waiters(released_waiters)

    new_state = %{
      state
      | pass: %{state.pass | registries_reloaded?: true},
        pending: MapSet.difference(state.pending, MapSet.new(pages)),
        priority: state.priority -- pages,
        waiters: waiters
    }

    {:reply, :ok, new_state}
  end

  def handle_call({:next_batch, remaining, links}, _from, state) do
    new_state = %{prune_tabs(state) | pending: remaining}

    # A save that arrived during the pass ends it here: its compile takes up what this one leaves
    # pending, with the pages its own edit reaches.
    if state.superseded_by do
      {:reply, :stop, new_state}
    else
      open_page_modules =
        MapSet.new(new_state.open_pages, fn {_instance_id, {page_module, _missing_since}} ->
          page_module
        end)

      batch =
        plan_batch(
          remaining,
          links,
          state.priority,
          open_page_modules,
          System.schedulers_online()
        )

      {:reply, batch, new_state}
    end
  end

  def handle_call(:open_pages, _from, state) do
    new_state = prune_tabs(state)

    reply =
      Map.new(new_state.open_pages, fn {instance_id, {page_module, _missing_since}} ->
        {instance_id, page_module}
      end)

    {:reply, reply, new_state}
  end

  @impl GenServer
  def handle_cast({:document_rendered, instance_id}, state) do
    document_versions =
      Map.put(
        state.document_versions,
        instance_id,
        {state.css_version, state.reload_version}
      )

    {:noreply, %{state | document_versions: document_versions}}
  end

  def handle_cast({:page_rendered, instance_id, page_module}, state) do
    open_pages = Map.put(state.open_pages, instance_id, {page_module, nil})
    {:noreply, %{state | open_pages: open_pages}}
  end

  # A tab whose document rendered before the last change to the app's assets may hold them in an
  # older version: the change can land while it loads or while its stream reconnects, when the tab
  # has no stream to be told. A reload brings changed CSS in too, so a tab that missed one is sent
  # only the reload.
  #
  # A tab live reload knows nothing of, rendered before the process started or forgotten since,
  # counts as having missed every CSS change, since a needless swap is harmless, and no reload,
  # since a needless one loses the tab's state. What it missed before can't be known, but from its
  # first stream on, a reload it misses is replayed like for any tab.
  #
  # Nothing else is recorded once sent: the stream can close before it writes the message. A tab
  # told twice swaps its stylesheets twice, or reloads once, since a reload renders a new document.
  def handle_cast({:replay_asset_change, pid, instance_id}, state) do
    unknown_tab_versions = {0, state.reload_version}

    {css_version, reload_version} =
      Map.get(state.document_versions, instance_id, unknown_tab_versions)

    cond do
      reload_version < state.reload_version -> send(pid, {:reload, :all})
      css_version < state.css_version -> send(pid, :css_changed)
      true -> :ok
    end

    document_versions = Map.put_new(state.document_versions, instance_id, unknown_tab_versions)

    {:noreply, %{state | document_versions: document_versions}}
  end

  def handle_cast({:replay_outcome, pid}, state) do
    if state.outcome, do: send(pid, state.outcome)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:file_event, _pid, :stop}, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:file_event, _pid, {file_path, events}}, state) do
    case classify_file_event(file_path, events) do
      {:code, target_file_path} ->
        if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

        # File change events are debounced to avoid multiple recompilations
        # when the same file is modified multiple times in quick succession.
        timer_ref =
          Process.send_after(self(), {:debounced_reload, target_file_path}, @debounce_delay)

        {:noreply, %{state | timer_ref: timer_ref}}

      {:static, static_path, kind} ->
        # Started once per batch of changes and not pushed back, so that a tool writing assets
        # continuously still gets its changes shown.
        asset_timer_ref =
          state.asset_timer_ref ||
            Process.send_after(self(), :debounced_asset_change, @asset_debounce_delay)

        {:noreply,
         %{
           state
           | asset_change: merge_asset_change(state.asset_change, kind),
             asset_timer_ref: asset_timer_ref,
             changed_static_paths: MapSet.put(state.changed_static_paths, static_path)
         }}

      :ignore ->
        # Ignore irrelevant files (backup files, temp files, etc.)
        {:noreply, state}
    end
  end

  # The asset path registry learns the changed static files first, and the manifest of the pages
  # rendered from then on with it, so that a tab told of the change finds them. Only CSS changed:
  # the tabs swap their stylesheets in place. Another asset the tabs load changed: every tab
  # reloads, which brings changed CSS in too. Only files the tabs aren't told about changed, such
  # as fonts or the cache manifest: the tabs are left alone. Independent of a live reload pass,
  # which rebuilds Hologram's bundles, not the app's assets.
  @impl GenServer
  def handle_info(:debounced_asset_change, state) do
    state.changed_static_paths
    |> MapSet.to_list()
    |> PathRegistry.update()

    ManifestCache.reload()

    new_state =
      case state.asset_change do
        :css ->
          Phoenix.PubSub.broadcast(Hologram.PubSub, "hologram_live_reload", :css_changed)
          %{state | css_version: state.css_version + 1}

        :other ->
          broadcast_reload(:all)
          %{state | reload_version: state.reload_version + 1}

        nil ->
          state
      end

    {:noreply,
     %{new_state | asset_change: nil, asset_timer_ref: nil, changed_static_paths: MapSet.new()}}
  end

  @impl GenServer
  def handle_info({:debounced_reload, target_file_path}, state) do
    new_state = %{state | timer_ref: nil}

    if new_state.pass do
      {:noreply, %{new_state | superseded_by: target_file_path}}
    else
      {:noreply, start_pass(target_file_path, new_state)}
    end
  end

  @impl GenServer
  def handle_info({ref, result}, %{pass: %{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])

    # A superseded pass reports nothing: the pass its save starts reports on the newer code, so the
    # tabs never show the outcome of code a newer save has replaced.
    new_state =
      if state.superseded_by == nil do
        outcome = to_outcome(result)
        Phoenix.PubSub.broadcast(Hologram.PubSub, "hologram_live_reload", outcome)
        %{state | outcome: outcome}
      else
        state
      end

    {:noreply, finish_pass(new_state)}
  end

  # A pass that crashed reports nothing to the tabs: what failed is live reload, not the code. A
  # compile refusing the code is not a crash (see reload/3).
  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{pass: %{ref: ref}} = state) do
    Logger.error("Hologram: live reload pass failed: " <> Exception.format_exit(reason))
    {:noreply, finish_pass(state)}
  end

  @doc """
  Waits until a live reload has built the given page's bundle, when it is pending, and has it built
  next. Returns at once for a page that is not pending, and when live reload is not running. The
  controller calls it before rendering a page in dev, so that a page the call graph could not tell
  the scheduler about (a path computed at runtime, a redirect) is still served with its current
  bundle.

  A request that waits longer than a minute, or whose live reload process goes away, gets the
  page's bundle as it is.
  """
  @spec await_page(module) :: :ok
  def await_page(page_module) do
    case GenServer.whereis(__MODULE__) do
      nil ->
        :ok

      pid ->
        try do
          GenServer.call(pid, {:await_page, page_module}, @await_page_timeout)
        catch
          :exit, _reason -> :ok
        end
    end
  end

  @doc """
  Returns the asset debounce delay in milliseconds.
  """
  @spec asset_debounce_delay :: pos_integer
  def asset_debounce_delay, do: @asset_debounce_delay

  @doc """
  Returns the debounce delay in milliseconds.
  """
  @spec debounce_delay :: pos_integer
  def debounce_delay, do: @debounce_delay

  # Public for tests, which drive the callbacks with a state of their own.
  @doc false
  @spec initial_state(any) :: map
  def initial_state(endpoint) do
    %{
      # What changed in the app's assets since the asset timer started: :css when only CSS did,
      # :other when another asset the tabs load did too, nil when neither did or no timer runs.
      asset_change: nil,
      asset_timer_ref: nil,
      # The static files and dirs changed since the asset timer started, by their paths relative to
      # the static dir.
      changed_static_paths: MapSet.new(),
      # Counts the CSS changes the tabs were told about, from 1, so that a tab rendered before this
      # process started, whose CSS it can't vouch for, counts as older (see replay_asset_change/2).
      css_version: 1,
      # The CSS version and the reload version each tab's document rendered with, by instance id,
      # or for a tab live reload knew nothing of, the ones it counts as having when its stream first
      # asked for a replay (see replay_asset_change/2 and prune_tabs/1).
      document_versions: %{},
      endpoint: endpoint,
      # What each tab showed at its last render, by instance id, with when it was first seen without
      # an SSE connection (nil while it holds one).
      open_pages: %{},
      # The outcome the last pass reported, as broadcast, nil before any did and while a pass runs.
      outcome: nil,
      # The live reload pass running, if any.
      pass: nil,
      # The pages the running or the last pass has not built.
      pending: MapSet.new(),
      # Pages asked for while pending, built first.
      priority: [],
      # Counts the changes to the app's assets other than CSS, which reload every tab.
      reload_version: 0,
      # A save that arrived during the pass, which starts the next one.
      superseded_by: nil,
      timer_ref: nil,
      # The requests waiting for a page's bundle, by page module.
      waiters: %{}
    }
  end

  @doc """
  Records that the tab with the given instance id rendered its document, and so loads the app's
  assets as they are now (see `replay_asset_change/2`). Does nothing when live reload is not
  running.
  """
  @spec document_rendered(String.t()) :: :ok
  def document_rendered(instance_id) do
    GenServer.cast(__MODULE__, {:document_rendered, instance_id})
  end

  @doc """
  Returns the page each open tab shows, by instance id: what each tab showed at its last render.
  A tab counts as open while it holds an SSE connection, and for a while without one: a page renders
  before its stream attaches, and a stream reconnects. A tab without one for longer is forgotten.
  """
  @spec open_pages() :: %{String.t() => module}
  def open_pages do
    GenServer.call(__MODULE__, :open_pages)
  end

  @doc """
  Records that the tab with the given instance id shows the given page, which a live reload then
  builds first. Does nothing when live reload is not running.
  """
  @spec page_rendered(String.t(), module) :: :ok
  def page_rendered(instance_id, page_module) do
    GenServer.cast(__MODULE__, {:page_rendered, instance_id, page_module})
  end

  @doc """
  Returns the pages to build next, from the pages still to build (`remaining`), in tiers:

    1. the priority pages, the ones requested while pending, in the order they were requested,
    2. else the pages open in tabs, all of them, since those are what the developer is looking at,
    3. else up to `batch_size` of the pages the open ones link to, which the developer may click next,
    4. else up to `batch_size` of the rest.

  The tiers only change the order: every page is built, and pages within tiers 2 to 4 are taken
  sorted, so that the order is the same for the same input. `links` maps each page to the pages it
  links to; an open page that is not left to build still contributes its links. Never empty while
  `remaining` is not.
  """
  @spec plan_batch(
          MapSet.t(module),
          %{module => MapSet.t(module)},
          [module],
          MapSet.t(module),
          pos_integer
        ) :: [module]
  def plan_batch(remaining, links, priority, open_pages, batch_size) do
    priority_pages =
      priority
      |> Enum.filter(&MapSet.member?(remaining, &1))
      |> Enum.uniq()

    open_remaining_pages = MapSet.intersection(open_pages, remaining)

    cond do
      priority_pages != [] ->
        priority_pages

      MapSet.size(open_remaining_pages) > 0 ->
        Enum.sort(open_remaining_pages)

      true ->
        linked_pages =
          open_pages
          |> Enum.flat_map(&Map.get(links, &1, []))
          |> MapSet.new()
          |> MapSet.intersection(remaining)

        tier = if MapSet.size(linked_pages) > 0, do: linked_pages, else: remaining

        tier
        |> Enum.sort()
        |> Enum.take(batch_size)
    end
  end

  @doc """
  Reloads the application after a file change by recompiling the Elixir code and then running the
  Hologram compile with the given options, `:next_batch` and `:bundles_built`, through which the
  scheduler orders the pages and reloads the tabs batch by batch (see `handle_call/3`). The
  runtime registries are reloaded once more at the end, for a compile that built no bundle.

  Returns `:ok` when the code compiled, and `{:error, lines}` when the Elixir compile or the
  Hologram compile refused it, the lines being what the overlay shows (see
  `Hologram.LiveReload.Diagnostic`). The Hologram compile's error is logged here, once: Phoenix
  prints the Elixir compile's output itself.
  """
  @spec reload(String.t() | nil, any, keyword) :: :ok | {:error, [[Diagnostic.segment()]]}
  def reload(_file_path, endpoint, opts) do
    with :ok <- reload_code(endpoint),
         :ok <- recompile_hologram(opts) do
      reload_runtime()
      :ok
    end
  end

  @doc """
  Sends the given process the change to the app's assets that the tab with the given instance id
  missed since its document rendered, as the message the change was broadcast as: `{:reload, :all}`
  when an asset other than CSS changed, else `:css_changed` when CSS did. A tab live reload knows
  nothing of, rendered before the process started or forgotten since, is sent `:css_changed` and
  no reload, and a reload it misses later is replayed. Sends nothing when live reload is not
  running.
  """
  @spec replay_asset_change(pid, String.t()) :: :ok
  def replay_asset_change(pid, instance_id) do
    GenServer.cast(__MODULE__, {:replay_asset_change, pid, instance_id})
  end

  @doc """
  Sends the given process the outcome the last live reload pass reported, the message it was
  broadcast as. Sends nothing while a pass runs, before any pass reported, and when live reload is
  not running. The outcome comes from the process that broadcasts the outcomes, so it arrives in
  order with them.
  """
  @spec replay_outcome(pid) :: :ok
  def replay_outcome(pid) do
    GenServer.cast(__MODULE__, {:replay_outcome, pid})
  end

  @doc """
  Returns the source directories that are watched for file changes. The app's static dir is
  watched too (see `watched_static_dir/0`).

  In a single-app project the directories are the project's own
  `:elixirc_paths`, joined to the project's directory.

  In an umbrella project they are the union of every child app's
  `:elixirc_paths`, joined to that child app's directory - so changes in any
  child app trigger a reload.
  """
  @spec watched_dirs :: [String.t()]
  def watched_dirs do
    case Mix.Project.apps_paths() do
      nil ->
        project_dir = active_project_dir()
        Enum.map(Mix.Project.config()[:elixirc_paths], &Path.join(project_dir, &1))

      apps_paths ->
        # Paths returned by Mix.Project.apps_paths/0 are relative to the umbrella
        # root, which is the cwd while the umbrella project is active.
        Enum.flat_map(apps_paths, fn {app, app_path} ->
          abs_app_path = Path.expand(app_path)
          Enum.map(app_elixirc_paths(app, abs_app_path), &Path.join(abs_app_path, &1))
        end)
    end
  end

  @doc """
  Returns file watcher options based on the operating system type.

  For macOS (Darwin), additional options are added for optimal performance:
  - `latency: 0` for immediate file change detection
  - `no_defer: true` to avoid deferring events

  For other operating systems, only the directories to watch are specified.
  """
  @spec watcher_opts({atom, atom}) :: keyword
  def watcher_opts({:unix, :darwin}) do
    [dirs: all_watched_dirs(), latency: 0, no_defer: true]
  end

  def watcher_opts(_os_type) do
    [dirs: all_watched_dirs()]
  end

  @doc """
  Returns the app's static dir, whose assets live reload watches besides the source files: the
  `priv/static` dir in the app's source dir. Not the one in the app's build dir
  (`_build/<env>/lib/<app>/priv/static`), which is a symbolic link to it.
  """
  @spec watched_static_dir :: String.t()
  def watched_static_dir do
    Path.join(Reflection.otp_app_dir(), "priv/static")
  end

  defp active_project_dir do
    # Mix keeps cwd at the active project's root.
    File.cwd!()
  end

  defp app_elixirc_paths(app, app_path) do
    Mix.Project.in_project(app, app_path, fn _module ->
      Mix.Project.config()[:elixirc_paths]
    end)
  end

  # The tabs' SSE streams forward it, and each tab reloads when its page is among the pages, or
  # when they are :all.
  defp broadcast_reload(pages) do
    Phoenix.PubSub.broadcast(Hologram.PubSub, "hologram_live_reload", {:reload, pages})
  end

  # A pass ended, whether it finished or failed: the pages requested during it are no longer
  # pulled forward, and a save that arrived during it starts the next pass. A request still waiting
  # is answered: its page is served with the bundle it had, and the reload event heals the tab once
  # the page is built.
  defp finish_pass(state) do
    reply_to_waiters(state.waiters)

    new_state = %{state | pass: nil, priority: [], waiters: %{}}

    case new_state.superseded_by do
      nil -> new_state
      file_path -> start_pass(file_path, %{new_state | superseded_by: nil})
    end
  end

  defp impl do
    Application.get_env(:hologram, :live_reload_impl, __MODULE__)
  end

  # Forgets the tabs closed since (see prune_open_pages/1): their pages and their documents.
  #
  # Only the documents of tabs open_pages drops go: a tab first seen through its stream (see
  # replay_asset_change/2) rendered no page this process saw, so its document stays. Those are the
  # tabs open when the process started, a handful, gone with the process.
  defp prune_tabs(state) do
    open_pages = prune_open_pages(state.open_pages)
    closed_tabs = Map.keys(state.open_pages) -- Map.keys(open_pages)

    %{
      state
      | document_versions: Map.drop(state.document_versions, closed_tabs),
        open_pages: open_pages
    }
  end

  # A tab seen without an SSE connection for longer than the grace period is closed, and its page is
  # no longer built first. A tab seen with one again is not missing any more.
  defp prune_open_pages(open_pages) do
    now = System.monotonic_time(:millisecond)

    Enum.reduce(open_pages, %{}, fn {instance_id, {page_module, missing_since}}, acc ->
      cond do
        SubscriptionRegistry.bindings_of(instance_id) != nil ->
          Map.put(acc, instance_id, {page_module, nil})

        missing_since == nil ->
          Map.put(acc, instance_id, {page_module, now})

        now - missing_since < @connection_grace_ms ->
          Map.put(acc, instance_id, {page_module, missing_since})

        true ->
          acc
      end
    end)
  end

  # The Hologram compile refusing the code is an outcome of the pass, not a crash of it: rescued
  # here, where the exception and its stacktrace are, logged once as the text a crash prints, and
  # returned as the lines the overlay shows. Exceptions only: an exit, as when the scheduler is gone
  # (see start_pass/2), is not an outcome to report.
  defp recompile_hologram(opts) do
    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    Mix.Tasks.Compile.Hologram.run([force?: true] ++ opts)
    :ok
  rescue
    error ->
      # Trimmed, since the logger ends the entry with a newline of its own.
      message =
        :error
        |> Exception.format(error, __STACKTRACE__)
        |> String.trim_trailing()

      Logger.error(message)

      {:error, Diagnostic.exception_to_lines(error, __STACKTRACE__)}
  end

  defp reload_code(endpoint) do
    case Phoenix.CodeReloader.reload(endpoint) do
      :ok -> :ok
      {:error, output} -> {:error, Diagnostic.to_lines(output)}
    end

    # TODO: this will be used in Hologram standalone version
    # Code.put_compiler_option(:ignore_module_conflict, true)
    # Kernel.ParallelCompiler.compile_to_path([file_path], Mix.Project.compile_path())
    # Code.put_compiler_option(:ignore_module_conflict, false)
    #
    # TODO: compiling here rather than through Phoenix would hand back the
    # compiler's diagnostics as structs, which Phoenix flattens to a string
    # before returning them. Broadcasting those instead of text would leave
    # Hologram.LiveReload.Diagnostic with nothing to read by shape - severity,
    # location and the stacktrace would all arrive as data. What the overlay
    # would take on in exchange is drawing the source excerpt itself, since
    # Elixir prints that rather than returning it.
  end

  defp reload_runtime do
    PageModuleResolver.reload()
    PathRegistry.reload()
    ManifestCache.reload()
    ChunkRegistry.reload()
    PageDigestRegistry.reload()
  end

  defp reply_to_waiters(waiters) do
    Enum.each(waiters, fn {_page_module, froms} ->
      Enum.each(froms, &GenServer.reply(&1, :ok))
    end)
  end

  # Determines what a file event is about: source code, with the file a live reload pass recompiles,
  # a file or dir of the app's static dir, with its path relative to the dir and whether the tabs
  # are told about it as CSS, as another asset or not at all, or nothing live reload acts on.
  defp classify_file_event(file_path, events) do
    case Path.extname(file_path) do
      ".ex" ->
        {:code, file_path}

      ".holo" ->
        ex_file = Path.rootname(file_path) <> ".ex"

        if File.exists?(ex_file) do
          {:code, ex_file}
        else
          :ignore
        end

      extension ->
        classify_static_event(file_path, extension, events)
    end
  end

  # Matched by the path's segments, not by the watched static dir as a prefix: the watcher can
  # report the path with a symbolic link on the way resolved. Phoenix's live reload matches its
  # patterns anywhere in the path for the same reason. What counts is what follows the last
  # priv/static in the path, since the project's own path can hold one too.
  defp classify_static_event(file_path, extension, events) do
    case static_subpath(file_path) do
      nil -> :ignore
      [] -> {:static, "", dir_change_kind(events)}
      subpath -> {:static, Path.join(subpath), static_change_kind(extension, events)}
    end
  end

  # A dir created, removed or renamed can change the URLs of the assets in it, so the tabs reload.
  # A dir that is only modified is one whose files changed, as the watcher on Windows reports along
  # with each file, and the files' own events tell the tabs about them.
  defp dir_change_kind(events) do
    if Enum.any?(events, &(&1 in @dir_change_events)), do: :other
  end

  # The segments that follow the last "priv", "static" pair, or nil when there is none.
  defp last_static_subpath(["priv", "static" | rest], _subpath) do
    last_static_subpath(rest, rest)
  end

  defp last_static_subpath([_segment | rest], subpath), do: last_static_subpath(rest, subpath)

  defp last_static_subpath([], subpath), do: subpath

  defp merge_asset_change(:other, _kind), do: :other
  defp merge_asset_change(asset_change, nil), do: asset_change
  defp merge_asset_change(_asset_change, kind), do: kind

  # A path with no extension is most likely a dir.
  defp static_change_kind(".css", _events), do: :css

  defp static_change_kind("", events), do: dir_change_kind(events)

  defp static_change_kind(extension, _events) when extension in @asset_extensions, do: :other

  defp static_change_kind(_extension, _events), do: nil

  # The segments of the path that follow the last priv/static, none for the static dir itself, or nil
  # when there is no priv/static in the path or the segments lead into a subdir whose files aren't
  # the app's assets, or name that subdir.
  defp static_subpath(file_path) do
    case last_static_subpath(Path.split(file_path), nil) do
      [subdir | _rest] = subpath -> if subdir not in @ignored_static_subdirs, do: subpath
      no_subpath -> no_subpath
    end
  end

  # A Phoenix project has a priv/static dir. The check keeps a project without one, or a dir deleted
  # meanwhile, from failing the watcher's backend.
  defp all_watched_dirs do
    static_dir = watched_static_dir()

    if File.dir?(static_dir) do
      [static_dir | watched_dirs()]
    else
      watched_dirs()
    end
  end

  # The pass runs in a task, unlinked, so that a failure in it is logged rather than taking this
  # process down, and so that this process stays free to answer the compile's calls: the compile
  # asks it for each batch and reports each one built.
  #
  # The callbacks address this process, not the registered name: a pass outliving a crash of this
  # process must not report to its replacement, which never started it. A call to the gone process
  # exits the pass instead, and the compile's lock is released on the way out.
  defp start_pass(file_path, state) do
    endpoint = state.endpoint
    scheduler = self()

    opts = [
      bundles_built: &GenServer.call(scheduler, {:bundles_built, &1}, :infinity),
      next_batch: &GenServer.call(scheduler, {:next_batch, &1, &2}, :infinity)
    ]

    task =
      Task.Supervisor.async_nolink(Hologram.LiveReload.TaskSupervisor, fn ->
        impl().reload(file_path, endpoint, opts)
      end)

    # The outcome is forgotten while the pass runs: the code it was about has changed, and a tab
    # reloaded or opened meanwhile must not be shown an error a newer save may have fixed. A stream
    # attached by the time the pass ends gets its outcome broadcast.
    %{state | outcome: nil, pass: %{ref: task.ref, registries_reloaded?: false}}
  end

  # The message a pass's outcome is broadcast as. The tabs' SSE streams forward it: a tab takes its
  # compilation error down once a pass compiled, and shows the error when a pass did not.
  defp to_outcome(:ok), do: :compiled
  defp to_outcome({:error, lines}), do: {:compilation_error, lines}
end
