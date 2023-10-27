defmodule Hologram.Commons.FileUtils do
  @doc """
  Lists files nested in the given path or paths. The results are sorted in ascending order.
  The result doesn't include directories.

  ## Examples

      iex> list_files_recursively("test/elixir/fixtures/commons/file_utils/list_files_recursively/dir_1")
      ["test/elixir/fixtures/commons/file_utils/list_files_recursively/dir_1/dir_3/file_5.txt",
       "test/elixir/fixtures/commons/file_utils/list_files_recursively/dir_1/dir_3/file_6.txt",
       "test/elixir/fixtures/commons/file_utils/list_files_recursively/dir_1/file_3.txt",
       "test/elixir/fixtures/commons/file_utils/list_files_recursively/dir_1/file_4.txt"]
  """
  @spec list_files_recursively(binary | list(binary)) :: list(binary)
  def list_files_recursively(paths), do: list_files_recursively(paths, true)

  defp list_files_recursively(paths, true) when is_list(paths) do
    paths
    |> Enum.map_join(" ", &inspect/1)
    |> list_files_recursively(false)
  end

  defp list_files_recursively(paths, true) when is_binary(paths) do
    paths
    |> inspect()
    |> list_files_recursively(false)
  end

  defp list_files_recursively(paths, false) when is_binary(paths) do
    find_command = "find #{paths} -type f 2>/dev/null | sort | uniq"
    {files, 0} = System.cmd("/bin/sh", ["-c", find_command], env: %{})
    String.split(files, "\n", trim: true)
  end
end
