defmodule Mix.Tasks.Holo.Assets.Build do
  def run(_) do
    Mix.Shell.cmd("npm install", cd: "deps/hologram/assets")
    Mix.Task.run("esbuild hologram --minify")
  end
end
