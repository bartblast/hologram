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

  @doc """
  Maps the function over the enumerable in concurrent tasks, at most `:max_concurrency` at a time
  (default: the number of online schedulers), and returns the results in the enumerable's order.
  A task that raises takes the caller down, as with `Task.async/1` and `Task.await/2`.
  """
  @spec map_concurrently(Enum.t(), (term -> term), keyword) :: list(term)
  def map_concurrently(enumerable, fun, opts \\ []) do
    max_concurrency = Keyword.get(opts, :max_concurrency, System.schedulers_online())

    enumerable
    |> Task.async_stream(fun, max_concurrency: max_concurrency, ordered: true, timeout: :infinity)
    |> Enum.map(fn {:ok, result} -> result end)
  end
end
