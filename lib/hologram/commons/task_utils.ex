defmodule Hologram.Commons.TaskUtils do
  def await_tasks(tasks) do
    Enum.map(tasks, &Task.await(&1, :infinity))
  end

  def map_async(enumerable, fun) do
    Enum.map(enumerable, fn elem ->
      Task.async(fn -> fun.(elem) end)
    end)
  end
end
