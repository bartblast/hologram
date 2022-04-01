# DEFER: refactor & test

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

  def handle_info({:file_event, _, _}, state) do
    # TODO: implement runtime reload
    # Runtime.stop()
    # Mix.Tasks.Compile.Hologram.run([])
    # Runtime.run()

    {:noreply, state}
  end
end
