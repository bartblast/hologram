defmodule Mix.Tasks.Holo.Test.CheckFileNames do
  use Mix.Task
  alias Hologram.Commons.FileUtils

  def run(args) do
    result =
      args
      |> FileUtils.list_files_recursively()
      |> Enum.all?(&String.ends_with?(&1, "_test.exs"))

    unless result, do: exit({:shutdown, 1})
    :ok
  end
end
