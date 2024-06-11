# TODO: test
defmodule Hologram.LiveReload do
  use GenServer

  alias Hologram.Assets.ManifestCache
  alias Hologram.Assets.PageDigestRegistry
  alias Hologram.Assets.PathRegistry
  alias Hologram.Commons.Reflection
  alias Hologram.Router.PageModuleResolver

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil)
  end

  def init(_opts) do
    {:ok, pid} =
      :os.type()
      |> watcher_opts()
      |> FileSystem.start_link()

    FileSystem.subscribe(pid)

    {:ok, Reflection.phoenix_endpoint()}
  end

  def handle_info({:file_event, _pid, :stop}, state) do
    {:noreply, state}
  end

  def handle_info({:file_event, _pid, {_file_path, [:renamed]}}, state) do
    {:noreply, state}
  end

  def handle_info({:file_event, _pid, {modified_file_path, _events}}, endpoint) do
    recompiled_file_path =
      case Path.extname(modified_file_path) do
        ".ex" ->
          modified_file_path

        ".holo" ->
          ex_file = Path.rootname(modified_file_path) <> ".ex"
          if File.exists?(ex_file), do: ex_file

        _fallback ->
          nil
      end

    if recompiled_file_path do
      Code.put_compiler_option(:ignore_module_conflict, true)
      Kernel.ParallelCompiler.compile_to_path([recompiled_file_path], Mix.Project.compile_path())
      Code.put_compiler_option(:ignore_module_conflict, false)

      Mix.Tasks.Compile.Hologram.run([])

      PageModuleResolver.reload()
      PathRegistry.reload()
      ManifestCache.reload()
      PageDigestRegistry.reload()

      endpoint.broadcast!("hologram", "reload", %{})
    end

    {:noreply, endpoint}
  end

  defp watched_dirs do
    root_dir = Reflection.root_dir()
    compiled_paths = Mix.Project.get().project()[:elixirc_paths]
    Enum.map(compiled_paths, &Path.join(root_dir, &1))
  end

  # This is macOS.
  defp watcher_opts({:unix, :darwin}) do
    [dirs: watched_dirs(), latency: 0, no_defer: true]
  end

  defp watcher_opts(_os_type) do
    [dirs: watched_dirs()]
  end
end
