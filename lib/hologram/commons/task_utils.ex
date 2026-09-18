defmodule Hologram.Commons.TaskUtils do
  @moduledoc false

  @doc """
  Maps the function over the enumerable in concurrent tasks, at most `:max_concurrency` at a time
  (default: the number of online schedulers), and returns the results in the enumerable's order.

  A task that raises, throws or exits does not take the caller down through the link: the failure is
  raised again in the caller, with the task's stacktrace, and the tasks still running are stopped.
  The caller's `rescue` and `after` clauses then run as for a failure of its own, which is what lets
  the compiler release its lock when a bundle fails.
  """
  @spec map_concurrently(Enum.t(), (term -> term), keyword) :: list(term)
  def map_concurrently(enumerable, fun, opts \\ []) do
    max_concurrency = Keyword.get(opts, :max_concurrency, System.schedulers_online())

    enumerable
    |> Task.async_stream(&capture_failure(fun, &1),
      max_concurrency: max_concurrency,
      ordered: true,
      timeout: :infinity
    )
    |> Enum.reduce_while([], fn
      {:ok, {:ok, result}}, results -> {:cont, [result | results]}
      {:ok, {:failed, _kind, _reason, _stacktrace} = failure}, _results -> {:halt, failure}
    end)
    |> reverse_or_reraise()
  end

  defp capture_failure(fun, elem) do
    {:ok, fun.(elem)}
  catch
    kind, reason -> {:failed, kind, reason, __STACKTRACE__}
  end

  defp reverse_or_reraise({:failed, kind, reason, stacktrace}) do
    :erlang.raise(kind, reason, stacktrace)
  end

  defp reverse_or_reraise(results), do: Enum.reverse(results)
end
