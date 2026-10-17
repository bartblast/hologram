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

  @doc """
  Starts live reload process, registered under its module name.

  ## Options

    * `:watch?` - whether to watch the source files (default: `true`). Tests start the process
      without watching the source tree.
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
    open_pages = prune_open_pages(state.open_pages)
    new_state = %{state | open_pages: open_pages, pending: remaining}

    # A save that arrived during the pass ends it here: its compile takes up what this one leaves
    # pending, with the pages its own edit reaches.
    if state.superseded_by do
      {:reply, :stop, new_state}
    else
      open_page_modules =
        MapSet.new(open_pages, fn {_instance_id, {page_module, _missing_since}} -> page_module end)

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
    open_pages = prune_open_pages(state.open_pages)

    reply =
      Map.new(open_pages, fn {instance_id, {page_module, _missing_since}} ->
        {instance_id, page_module}
      end)

    {:reply, reply, %{state | open_pages: open_pages}}
  end

  @impl GenServer
  def handle_cast({:page_rendered, instance_id, page_module}, state) do
    open_pages = Map.put(state.open_pages, instance_id, {page_module, nil})
    {:noreply, %{state | open_pages: open_pages}}
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
  def handle_info({:file_event, _pid, {file_path, _events}}, state) do
    case should_process_file_event?(file_path) do
      {:ok, target_file_path} ->
        if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

        # File change events are debounced to avoid multiple recompilations
        # when the same file is modified multiple times in quick succession.
        timer_ref =
          Process.send_after(self(), {:debounced_reload, target_file_path}, @debounce_delay)

        {:noreply, %{state | timer_ref: timer_ref}}

      :ignore ->
        # Ignore irrelevant files (backup files, temp files, etc.)
        {:noreply, state}
    end
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
  Returns the debounce delay in milliseconds.
  """
  @spec debounce_delay :: pos_integer
  def debounce_delay, do: @debounce_delay

  # Public for tests, which drive the callbacks with a state of their own.
  @doc false
  @spec initial_state(any) :: map
  def initial_state(endpoint) do
    %{
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
      # A save that arrived during the pass, which starts the next one.
      superseded_by: nil,
      timer_ref: nil,
      # The requests waiting for a page's bundle, by page module.
      waiters: %{}
    }
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
  Returns the list of directories that are watched for file changes.

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
    [dirs: watched_dirs(), latency: 0, no_defer: true]
  end

  def watcher_opts(_os_type) do
    [dirs: watched_dirs()]
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

  # Determines whether to process a file event and returns the target file to reload
  defp should_process_file_event?(file_path) do
    case Path.extname(file_path) do
      ".ex" ->
        {:ok, file_path}

      ".holo" ->
        ex_file = Path.rootname(file_path) <> ".ex"

        if File.exists?(ex_file) do
          {:ok, ex_file}
        else
          :ignore
        end

      _fallback ->
        :ignore
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
