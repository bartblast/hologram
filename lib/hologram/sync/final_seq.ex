defmodule Hologram.Sync.FinalSeq do
  @moduledoc false

  # The highest oplog serial this node knows to be final: every save at or below it has ended. A
  # query reads it to tell `server_created_seq` and `server_updated_seq` that are final from ones a
  # save still running might yet be ordered below, and hides the rest as nil.
  #
  # Kept in an atomics cell, so that every query reads it without a call to the dispatcher that
  # works it out. The cell is made on the first publish; a node that has published nothing answers
  # 0, below every serial, so no number reads as final until the dispatcher's first round has run.
  #
  # A render pins the limit once, so that every query of one page reads the same one: a number
  # shown in one list and hidden in another would leave the server's HTML disagreeing with what the
  # browser works out from the rows the page carries. The pin is the process's own: a process the
  # render starts reads the published limit, which may have moved past the pinned one.
  #
  # The sandbox mark is the process's own too, so a process a test starts reads the published
  # limit, 0 unless a dispatcher has run, and every number it reads is nil.

  alias Hologram.DB.Connection

  @pin_key {__MODULE__, :pin}
  @ref_key {__MODULE__, :ref}

  # Above every serial: a limit nothing is above.
  @all_final 9_223_372_036_854_775_807

  @doc """
  Returns a limit every number is at or below, which a read that shows numbers raw binds.
  """
  @spec all_final() :: pos_integer
  def all_final, do: @all_final

  @doc """
  Returns the limit: the pinned one while a pin is set, else the published one, or 0 when nothing
  was published.

  A process in a test's sandbox reads every number as final. Its transaction never commits, so no
  dispatcher sees its saves, and every number it can read is at or below the sequence's last value
  anyway - only a number written by hand above it reads differently than it would there.
  """
  @spec current() :: non_neg_integer
  def current do
    cond do
      pinned = Process.get(@pin_key) -> pinned
      Connection.sandboxed?() -> @all_final
      true -> published()
    end
  end

  @doc """
  Publishes a new limit for every process on this node.
  """
  @spec publish(non_neg_integer) :: :ok
  def publish(seq) when is_integer(seq) and seq >= 0 do
    :atomics.put(ref(), 1, seq)
  end

  @doc """
  Runs the function with the limit pinned at the one published now, and restores what was pinned
  before once it returns or raises. A pin already set is kept, so a pinned render calling another
  keeps one limit throughout.
  """
  @spec with_pinned((-> result)) :: result when result: any
  def with_pinned(fun) do
    with_pinned(current(), fun)
  end

  @doc """
  Runs the function with the limit pinned at the given one, and restores what was pinned before
  once it returns or raises.
  """
  @spec with_pinned(non_neg_integer, (-> result)) :: result when result: any
  def with_pinned(seq, fun) when is_integer(seq) and seq >= 0 do
    previous = Process.put(@pin_key, seq)

    try do
      fun.()
    after
      if previous, do: Process.put(@pin_key, previous), else: Process.delete(@pin_key)
    end
  end

  @doc """
  Returns the limit this node's dispatcher last published, or 0 when nothing was published, with
  no pin or sandbox in the way - what a sync session joining takes as final beside the read edge.
  """
  @spec published() :: non_neg_integer
  def published do
    case :persistent_term.get(@ref_key, nil) do
      nil -> 0
      ref -> :atomics.get(ref, 1)
    end
  end

  # Made once per node and never replaced: a persistent term put again makes every process copy it
  # anew. Only the node's dispatcher publishes, so two first publishes never race to make it.
  defp ref do
    case :persistent_term.get(@ref_key, nil) do
      nil ->
        ref = :atomics.new(1, signed: true)
        :persistent_term.put(@ref_key, ref)
        ref

      ref ->
        ref
    end
  end
end
