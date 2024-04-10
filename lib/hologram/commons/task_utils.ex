defmodule Hologram.Commons.TaskUtils do
  def async_many(enumerable, fun) do
    Enum.map(enumerable, fn elem ->
      Task.async(fn -> fun.(elem) end)
    end)
  end
end
