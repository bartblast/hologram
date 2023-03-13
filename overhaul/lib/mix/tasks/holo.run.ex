defmodule Mix.Tasks.Holo.Run do
  def run(_) do
    Mix.Task.run("holo.assets.build", [])

    if Mix.env() == :prod do
      Mix.Task.run("holo.assets.clean")
      Mix.Task.run("phx.digest")
    end

    Mix.Task.run("phx.server")
  end
end
