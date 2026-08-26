defmodule Hologram.Mutation.Ref do
  @moduledoc false

  # The batch of client writes the calling process is applying, for the extent of its transaction.
  # The outbox reads it and stamps every effect written meanwhile with it, so a client can tell
  # the effects of its own writes apart from everyone else's when they arrive on the stream.
  #
  # Process-local and not inherited, exactly like the ambient actor beside it: work moved off the
  # applying process is not part of the batch, and an effect it writes is nobody's.

  @key {__MODULE__, :ref}

  @doc """
  Returns the batch the calling process is applying, or nil when it is applying none.
  """
  @spec get() :: %{client_id: String.t(), seq: non_neg_integer} | nil
  def get do
    Process.get(@key)
  end

  @doc """
  Runs the given function with the given batch set as the calling process' one and returns its result.
  The batch set before the call is restored afterwards, raised exceptions included, so nested calls compose.
  """
  @spec with_ref(%{client_id: String.t(), seq: non_neg_integer}, (-> any)) :: any
  def with_ref(ref, fun) do
    previous_ref = Process.get(@key)
    Process.put(@key, ref)

    try do
      fun.()
    after
      restore(previous_ref)
    end
  end

  defp restore(nil), do: Process.delete(@key)

  defp restore(ref), do: Process.put(@key, ref)
end
