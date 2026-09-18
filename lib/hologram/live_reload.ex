defmodule Hologram.LiveReload do
  @moduledoc false

  use GenServer

  require Logger

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
  `:next_batch` and `:bundles_built` (see `Mix.Tasks.Compile.Hologram`).
  """
  @callback reload(String.t() | nil, any, keyword) :: :ok

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
  def handle_call({:bundles_built, built}, _from, state) do
    pages = List.delete(built, :runtime)

    # The first batch of a pass is where the registries learn what the compile wrote: the pages and
    # routes of the module info dump, the static files, among them a new runtime bundle, and the page
    # digests. Later batches change the page digests only.
    if state.pass.registries_reloaded? do
      PageDigestRegistry.reload()
    else
      reload_runtime()
    end

    # A rebuilt runtime bundle no longer matches the page bundles any tab holds, so every tab
    # reloads, the ones on pages this pass has not built yet included: they ask for their page,
    # which is then built next.
    if :runtime in built do
      broadcast_reload(:all)
    else
      broadcast_reload(pages)
    end

    new_state = %{
      state
      | pass: %{state.pass | registries_reloaded?: true},
        pending: MapSet.difference(state.pending, MapSet.new(pages))
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
        open_pages
        |> Map.values()
        |> MapSet.new()

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
    {:reply, open_pages, %{state | open_pages: open_pages}}
  end

  @impl GenServer
  def handle_cast({:page_rendered, instance_id, page_module}, state) do
    {:noreply, %{state | open_pages: Map.put(state.open_pages, instance_id, page_module)}}
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
  def handle_info({ref, _result}, %{pass: %{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, finish_pass(state)}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{pass: %{ref: ref}} = state) do
    Logger.error("Hologram: live reload pass failed: #{inspect(reason)}")
    {:noreply, finish_pass(state)}
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
      # What each tab showed at its last render, by instance id.
      open_pages: %{},
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
  Returns the page each open tab shows, by instance id: what each tab showed at its last render,
  for the tabs that still hold an SSE connection. The tabs that do not are forgotten.
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

  If code reloading fails, broadcasts a compilation error instead.
  """
  @spec reload(String.t() | nil, any, keyword) :: :ok
  def reload(_file_path, endpoint, opts) do
    case reload_code(endpoint) do
      :ok ->
        recompile_hologram(opts)
        reload_runtime()
        :ok

      {:error, output} ->
        broadcast_compilation_error(output)
    end
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

  defp broadcast_compilation_error(output) do
    lines = Diagnostic.to_lines(output)

    Phoenix.PubSub.broadcast(
      Hologram.PubSub,
      "hologram_live_reload",
      {:compilation_error, lines}
    )
  end

  # The tabs' SSE streams forward it, and each tab reloads when its page is among the pages, or
  # when they are :all.
  defp broadcast_reload(pages) do
    Phoenix.PubSub.broadcast(Hologram.PubSub, "hologram_live_reload", {:reload, pages})
  end

  # A pass ended, whether it finished or failed: the pages requested during it are no longer
  # pulled forward, and a save that arrived during it starts the next pass.
  defp finish_pass(state) do
    new_state = %{state | pass: nil, priority: []}

    case new_state.superseded_by do
      nil -> new_state
      file_path -> start_pass(file_path, %{new_state | superseded_by: nil})
    end
  end

  defp impl do
    Application.get_env(:hologram, :live_reload_impl, __MODULE__)
  end

  # The tabs that no longer hold an SSE connection are closed, so their pages are not built first.
  defp prune_open_pages(open_pages) do
    Map.filter(open_pages, fn {instance_id, _page_module} ->
      SubscriptionRegistry.bindings_of(instance_id) != nil
    end)
  end

  defp recompile_hologram(opts) do
    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    Mix.Tasks.Compile.Hologram.run([force?: true] ++ opts)
  end

  defp reload_code(endpoint) do
    Phoenix.CodeReloader.reload(endpoint)

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
    PageDigestRegistry.reload()
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
  defp start_pass(file_path, state) do
    endpoint = state.endpoint

    opts = [
      bundles_built: &GenServer.call(__MODULE__, {:bundles_built, &1}, :infinity),
      next_batch: &GenServer.call(__MODULE__, {:next_batch, &1, &2}, :infinity)
    ]

    task =
      Task.Supervisor.async_nolink(Hologram.LiveReload.TaskSupervisor, fn ->
        impl().reload(file_path, endpoint, opts)
      end)

    %{state | pass: %{ref: task.ref, registries_reloaded?: false}}
  end
end
