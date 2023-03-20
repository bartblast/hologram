defmodule Mix.Tasks.Holo.Test.CheckFileNames do
  use Mix.Task
  alias Hologram.Commons.FileUtils

  @moduledoc """
  Checks whether test scripts have valid file names,
  i.e. they end with "_test" and have ".exs" file extension.

  If there are any invalid file names, the task exits with code 1.

  Scripts not adhering to the aforementioned rules wouldn't be picked up by the mix test task.

  ## Examples

      $ mix holo.test.check_file_names test/elixir/hologram/compiler test/elixir/hologram/template
  """

  @doc false
  def run(args) do
    invalid_file_names =
      args
      |> FileUtils.list_files_recursively()
      |> Enum.reject(&String.ends_with?(&1, "_test.exs"))

    if Enum.any?(invalid_file_names) do
      IO.puts(red("Found invalid file names:"))
      Enum.each(invalid_file_names, &IO.puts(red(&1)))
      exit({:shutdown, 1})
    end

    :ok
  end

  defp red(text) do
    IO.ANSI.red() <> text <> IO.ANSI.reset()
  end
end
