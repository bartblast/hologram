defmodule Mix.Tasks.Holo.Test.CheckFileNames do
  use Mix.Task
  alias Hologram.Commons.FileUtils

  @moduledoc """
  Checks whether test scripts have valid file names (end with _test.exs),
  so that they can be picked up by the mix test task.
  """

  def run(args) do
    result =
      args
      |> FileUtils.list_files_recursively()
      |> Enum.all?(&String.ends_with?(&1, "_test.exs"))

    unless result, do: exit({:shutdown, 1})
    :ok
  end
end
