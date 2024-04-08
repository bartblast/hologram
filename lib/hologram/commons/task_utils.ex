defmodule Hologram.Commons.TaskUtils do
  def map_async(enumerable, fun) do
    Enum.map(enumerable, fn elem ->
      Task.async(fn -> fun.(elem) end)
    end)
  end
end
