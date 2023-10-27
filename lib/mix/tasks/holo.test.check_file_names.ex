# credo:disable-for-this-file Credo.Check.Refactor.IoPuts
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
  alias Hologram.Commons.StringUtils

  @doc false
  @impl Mix.Task
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

  defp print_result_and_exit([]) do
    print_colored("All test scripts have valid file names.", :green)
  end

  defp print_result_and_exit(invalid_file_names) do
    print_colored("Found test scripts with invalid file names:", :red)

    Enum.each(invalid_file_names, fn invalid_file_name ->
      invalid_file_name
      |> StringUtils.prepend("  * ")
      |> print_colored(:red)
    end)

    exit({:shutdown, 1})
  end

  @spec print_colored(String.t(), :green | :red) :: :ok
  defp print_colored(text, color) when color in ~w[green red]a do
    IO.ANSI
    |> apply(color, [])
    |> then(&StringUtils.wrap(text, &1, IO.ANSI.reset()))
    |> IO.puts()
  end
end
