defmodule Mix.Tasks.Hologram.Tmp do
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    IO.puts("in Mix.Tasks.Hologram.Tmp")
    Mix.shell().info(Enum.join(args, " "))
  end
end
