defmodule Hologram.LiveReload do
  @moduledoc false

  use GenServer

  alias Hologram.Assets.ManifestCache
  alias Hologram.Assets.PageDigestRegistry
  alias Hologram.Assets.PathRegistry
  alias Hologram.LiveReload.Diagnostic
  alias Hologram.Realtime.SubscriptionRegistry
  alias Hologram.Reflection
  alias Hologram.Router.PageModuleResolver

  @doc """
  Reloads the given file path using the given endpoint.
  """
  @callback reload(String.t(), any) :: :ok

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
  def handle_call(:open_pages, _from, state) do
    open_pages =
      Map.filter(state.open_pages, fn {instance_id, _page_module} ->
        SubscriptionRegistry.bindings_of(instance_id) != nil
      end)

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
    impl().reload(target_file_path, state.endpoint)
    {:noreply, %{state | timer_ref: nil}}
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
  Reloads the application after a file change by recompiling Elixir code,
  recompiling Hologram components, reloading Hologram runtime, and 
  broadcasting reload notifications to connected clients.

  If code reloading fails, broadcasts a compilation error instead.
  """
  @spec reload(String.t(), any) :: :ok
  def reload(_file_path, endpoint) do
    case reload_code(endpoint) do
      :ok ->
        recompile_hologram()
        reload_runtime()
        broadcast_reload()

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

  # Every tab reloads, as it did when the WebSocket carried this. The tabs' SSE streams forward it.
  defp broadcast_reload do
    Phoenix.PubSub.broadcast(Hologram.PubSub, "hologram_live_reload", {:reload, :all})
  end

  defp impl do
    Application.get_env(:hologram, :live_reload_impl, __MODULE__)
  end

  defp recompile_hologram do
    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    Mix.Tasks.Compile.Hologram.run(force?: true)
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
end
