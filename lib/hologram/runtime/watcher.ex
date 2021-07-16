# DEFER: test

defmodule Hologram.Runtime.Watcher do
  use GenServer

  @cwd File.cwd!()

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_) do
    {:ok, pid} = FileSystem.start_link(dirs: dirs())
    FileSystem.subscribe(pid)

    {:ok, pid}
  end

  def handle_info({:file_event, _, :stop}, state) do
    {:noreply, state}
  end
  
  def handle_info({:file_event, _, _}, state) do
    Mix.Tasks.Compile.Hologram.run(:no_args)
    {:noreply, state}
  end

  defp dirs do
    ["/config", "/lib"]
    |> Enum.map(&(@cwd <> &1))
  end
end
