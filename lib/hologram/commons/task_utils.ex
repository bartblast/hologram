defmodule Hologram.Commons.TaskUtils do
  @moduledoc false

  @doc """
  Starts multiple tasks.
  """
  @spec async_many(Enum.t(), fun) :: list(Task.t())
  def async_many(enumerable, fun) do
    Enum.map(enumerable, fn elem ->
      Task.async(fn -> fun.(elem) end)
    end)
  end
end
