defmodule Hologram.LiveReload do
  @moduledoc false

  use GenServer

  alias Hologram.Assets.ManifestCache
  alias Hologram.Assets.PageDigestRegistry
  alias Hologram.Assets.PathRegistry
  alias Hologram.Reflection
  alias Hologram.Router.PageModuleResolver

  @doc """
  Reloads the given file path using the given endpoint.
  """
  @callback reload(String.t(), any) :: :ok

  # in milliseconds
  @debounce_delay 1_000

  @doc """
  Starts live reload process.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil)
  end

  @impl GenServer
  def init(_opts) do
    {:ok, pid} =
      :os.type()
      |> watcher_opts()
      |> FileSystem.start_link()

    FileSystem.subscribe(pid)

    {:ok, %{endpoint: Reflection.phoenix_endpoint(), timer_ref: nil}}
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
    Phoenix.PubSub.broadcast(
      Hologram.PubSub,
      "hologram_live_reload",
      {:compilation_error, output}
    )
  end

  defp broadcast_reload do
    Phoenix.PubSub.broadcast(Hologram.PubSub, "hologram_live_reload", :reload)
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
