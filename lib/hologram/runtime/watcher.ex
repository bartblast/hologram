# DEFER: refactor & test
# DEFER: consider separating reloading related code to CodeReload module

defmodule Hologram.Runtime.Watcher do
  use GenServer

  alias Hologram.Compiler.Reflection
  alias Hologram.Runtime

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_) do
    app_path = Reflection.app_path()
    {:ok, pid} = FileSystem.start_link(dirs: [app_path])
    FileSystem.subscribe(pid)

    {:ok, pid}
  end

  def handle_info({:file_event, _, :stop}, state) do
    {:noreply, state}
  end

  def handle_info({:file_event, _, {file_path, _}}, state) do
    # Make sure the compile task has the new version in memory immediately
    IEx.Helpers.c(file_path)

    Mix.Tasks.Compile.Hologram.run([])
    Runtime.reload()
    endpoint().broadcast!("hologram", "reload", %{})

    {:noreply, state}
  end

  defp endpoint do
    Application.fetch_env!(:hologram, :endpoint)
  end
end
