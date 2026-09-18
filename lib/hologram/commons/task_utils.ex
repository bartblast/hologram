defmodule Hologram.Commons.TaskUtils do
  @moduledoc false

  @doc """
  Maps the function over the enumerable in concurrent tasks, at most `:max_concurrency` at a time
  (default: the number of online schedulers), and returns the results in the enumerable's order.

  A task that raises, throws or exits does not take the caller down through the link: the failure is
  raised again in the caller, with the task's stacktrace, as soon as it happens, and the tasks still
  running are stopped. The caller's `rescue` and `after` clauses then run as for a failure of its
  own, which is what lets the compiler release its lock when a bundle fails.
  """
  @spec map_concurrently(Enum.t(), (term -> term), keyword) :: list(term)
  def map_concurrently(enumerable, fun, opts \\ []) do
    max_concurrency = Keyword.get(opts, :max_concurrency, System.schedulers_online())

    # Taken as they finish rather than in order: in order, a failure would wait behind every
    # unfinished task ahead of it while the stream went on starting the rest. The index puts the
    # results back in the enumerable's order.
    enumerable
    |> Stream.with_index()
    |> Task.async_stream(
      fn {elem, index} -> {index, capture_failure(fun, elem)} end,
      max_concurrency: max_concurrency,
      ordered: false,
      timeout: :infinity
    )
    |> Enum.reduce_while([], fn
      {:ok, {index, {:ok, result}}}, results ->
        {:cont, [{index, result} | results]}

      {:ok, {_index, {:failed, _kind, _reason, _stacktrace} = failure}}, _results ->
        {:halt, failure}
    end)
    |> sort_or_reraise()
  end

  defp capture_failure(fun, elem) do
    {:ok, fun.(elem)}
  catch
    kind, reason -> {:failed, kind, reason, __STACKTRACE__}
  end

  defp sort_or_reraise({:failed, kind, reason, stacktrace}) do
    :erlang.raise(kind, reason, stacktrace)
  end

  defp sort_or_reraise(indexed_results) do
    indexed_results
    |> Enum.sort_by(fn {index, _result} -> index end)
    |> Enum.map(fn {_index, result} -> result end)
  end
end
