defmodule Mix.Tasks.Holo.Assets.Clean do
  def run(_) do
    Mix.Task.run("phx.digest.clean", ["--all"])
  end
end
