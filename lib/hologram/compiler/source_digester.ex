# DEFER: test
defmodule Hologram.Compiler.SourceDigester do
  def digest(paths) do
    data =
      Enum.reduce(paths, [], &(&2 ++ list_files(&1)))
      |> Enum.reduce(%{}, &Map.put(&2, &1, File.read!(&1)))
      |> :erlang.term_to_binary()

    :crypto.hash(:md5, data)
  end

  defp list_files(path) do
    cond do
      File.regular?(path) -> [path]

      File.dir?(path) ->
        File.ls!(path)
        |> Enum.map(&Path.join(path, &1))
        |> Enum.map(&list_files/1)
        |> Enum.concat()

      true -> []
    end
  end
end
