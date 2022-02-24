defmodule Mix.Tasks.Holo.Assets.Build do
  def run(_) do
    Mix.Task.run("cmd cd deps/hologram/assets && npm install")
    Mix.Task.run("esbuild hologram --minify")
  end
end
