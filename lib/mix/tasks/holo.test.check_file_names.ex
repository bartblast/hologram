defmodule Mix.Tasks.Holo.Test.CheckFileNames do
  @moduledoc """
  Checks if any test scripts have invalid file names.
  File name is valid if it ends with "_test" suffix and has ".exs" extension.
  If there are any invalid file names, the task exits with code 1.

  Scripts not adhering to the aforementioned rules wouldn't be picked up by the mix test task.

  ## Examples

      $ mix holo.test.check_file_names test/elixir/hologram/compiler test/elixir/hologram/template
  """

  use Mix.Task
  alias Hologram.Commons.FileUtils

  @doc false
  def run(args) do
    args
    |> find_invalid_file_names()
    |> print_result_and_exit()
  end

  defp find_invalid_file_names(paths) do
    paths
    |> FileUtils.list_files_recursively()
    |> Enum.reject(&String.ends_with?(&1, "_test.exs"))
  end

  defp green(text) do
    IO.ANSI.green() <> text <> IO.ANSI.reset()
  end

  defp print_result_and_exit([]) do
    "All test scripts have valid file names."
    |> green()
    # credo:disable-for-next-line Credo.Check.Refactor.IoPuts
    |> IO.puts()

    :ok
  end

  defp print_result_and_exit(invalid_file_names) do
    "Found test scripts with invalid file names:"
    |> red()
    # credo:disable-for-next-line Credo.Check.Refactor.IoPuts
    |> IO.puts()

    # credo:disable-for-next-line Credo.Check.Refactor.IoPuts
    Enum.each(invalid_file_names, &IO.puts(red("  * " <> &1)))

    exit({:shutdown, 1})
  end

  defp red(text) do
    IO.ANSI.red() <> text <> IO.ANSI.reset()
  end
end
