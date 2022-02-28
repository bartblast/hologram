defmodule Mix.Tasks.Holo.Assets.Build do
  def run(_) do
    Mix.Shell.cmd("npm install", [cd: "deps/hologram/assets", quiet: true], &(&1))
    Mix.Task.run("esbuild hologram --minify")
  end
end
