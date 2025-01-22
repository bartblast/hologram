defmodule Hologram.Commons.FileUtils do
  @moduledoc false

  alias Hologram.Commons.Types, as: T

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
  @spec list_files_recursively(T.file_path() | list(T.file_path())) :: list(T.file_path())
  def list_files_recursively(path_or_paths)

  def list_files_recursively(paths) when is_list(paths) do
    paths
    |> Enum.map(&list_files_recursively/1)
    |> Enum.concat()
    |> Enum.uniq()
    |> Enum.sort()
  end

  def list_files_recursively(path) do
    cond do
      File.regular?(path) ->
        [path]

      File.dir?(path) ->
        path
        |> File.ls!()
        |> Enum.map(&Path.join(path, &1))
        |> Enum.map(&list_files_recursively/1)
        |> Enum.concat()
        |> Enum.sort()

      true ->
        raise ArgumentError, ~s(Invalid path: "#{path}")
    end
  end

  @doc """
  Removes the given dir (including all its contents) and creates an empty dir with the same name and path.
  """
  @spec recreate_dir(T.file_path()) :: :ok
  def recreate_dir(dir_path) do
    File.rm_rf!(dir_path)
    File.mkdir_p!(dir_path)

    :ok
  end
end
