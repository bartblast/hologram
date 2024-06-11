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
    root_dir = Reflection.root_dir()
    compiled_paths = Mix.Project.get().project()[:elixirc_paths]
    watched_dirs = Enum.map(compiled_paths, &Path.join(root_dir, &1))

    {:ok, pid} = FileSystem.start_link(dirs: watched_dirs)
    FileSystem.subscribe(pid)

    {:ok, Reflection.phoenix_endpoint()}
  end

  def handle_info({:file_event, _pid, :stop}, state) do
    {:noreply, state}
  end

  def handle_info({:file_event, _pid, {_file_path, _events}}, endpoint) do
    Mix.Tasks.Compile.Hologram.run([])

    PageModuleResolver.reload()
    PathRegistry.reload()
    ManifestCache.reload()
    PageDigestRegistry.reload()

    endpoint.broadcast!("hologram", "reload", %{})

    {:noreply, endpoint}
  end
end
