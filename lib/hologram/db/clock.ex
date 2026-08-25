defmodule Hologram.DB.Clock do
  @moduledoc false

  # The stamps the server tier authors as column revisions: wall_clock_ms * 1024 + logical,
  # strictly increasing per node and never behind the wall clock. 43 bits of milliseconds and 10
  # of logical counter keep a stamp under JavaScript's 53-bit safe integer, since a client reads
  # the same number off the wire and stamps its own writes from a clock of the same shape.
  #
  # Held in an atomics array behind a persistent term - a stamp is a compare-and-swap, with no
  # process in the way of a write path every entity write goes through.

  @key {__MODULE__, :counter}

  @logical_span 1024

  @doc """
  Creates this node's clock, unless it already has one.

  Keeping an existing counter is what makes the strictly-increasing claim survive a restart of
  the supervisor holding it: a fresh counter starts below the stamps already handed out, and
  within one millisecond the wall clock does not yet lift it back above them.
  """
  @spec init() :: :ok
  def init do
    case :persistent_term.get(@key, nil) do
      nil -> :persistent_term.put(@key, :atomics.new(1, signed: false))
      _counter -> :ok
    end
  end

  @doc """
  Returns the next stamp, above every stamp this node has already returned and at or above the
  current wall clock.
  """
  @spec stamp() :: pos_integer
  def stamp do
    @key
    |> :persistent_term.get()
    |> advance()
  end

  @doc """
  Returns the wall clock, in milliseconds, that the given stamp was taken at.
  """
  @spec wall_clock_ms(pos_integer) :: non_neg_integer
  def wall_clock_ms(stamp) do
    div(stamp, @logical_span)
  end

  # A lost race means another caller took the value this one read, so what it computed from it is
  # no longer next - it reads the winner's value and computes again.
  defp advance(counter) do
    last = :atomics.get(counter, 1)
    next = max(last + 1, System.os_time(:millisecond) * @logical_span)

    case :atomics.compare_exchange(counter, 1, last, next) do
      :ok -> next
      _current -> advance(counter)
    end
  end
end
