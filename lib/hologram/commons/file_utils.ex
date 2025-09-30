defmodule Hologram.Commons.FileUtils do
  @moduledoc false

  alias Hologram.Commons.Types, as: T

  @doc """
  Copies a file to a destination, creating parent directories as needed.
  """
  @spec cp_p!(T.file_path(), T.file_path()) :: :ok
  def cp_p!(source_path, dest_path) do
    dest_path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.cp!(source_path, dest_path)
  end

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
    rm_rf_with_retries!(dir_path, 5, 10)
    File.mkdir_p!(dir_path)

    :ok
  end

  @doc """
  Recursively removes the given file or directory (and its contents) with retries.
  Succeeds only when the path no longer exists.
  Raises if the path still exists after max_attempts.
  """
  @spec rm_rf_with_retries!(T.file_path(), pos_integer, non_neg_integer) :: :ok
  def rm_rf_with_retries!(path, max_attempts, sleep_ms) do
    Enum.reduce_while(1..max_attempts, nil, fn attempt, _acc ->
      case File.rm_rf(path) do
        {:ok, _files_and_dirs} -> :ok
        {:error, _reason, _partial} -> :error
      end

      cond do
        not File.exists?(path) ->
          {:halt, :ok}

        attempt < max_attempts ->
          Process.sleep(sleep_ms)
          {:cont, nil}

        true ->
          raise "Failed to fully remove #{path} after #{max_attempts} attempts"
      end
    end)
  end

  @doc """
  Writes content to a file, creating parent directories as needed.
  """
  @spec write_p!(T.file_path(), iodata()) :: :ok
  def write_p!(file_path, content) do
    file_path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(file_path, content)
  end
end
