defmodule Hologram.Commons.FileUtils do
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
        File.ls!(path)
        |> Enum.map(&Path.join(path, &1))
        |> Enum.map(&list_files_recursively/1)
        |> Enum.concat()
        |> Enum.sort()
    end
  end
end
