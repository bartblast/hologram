defmodule Hologram.Sync.FinalLimit do
  @moduledoc false

  # How far this node knows the oplog's serials to be final: every serial at or below the limit
  # belongs to a save that has ended, so no row holding one can still appear.
  #
  # A serial is handed out when a save writes, long before it commits, so the highest one says
  # nothing by itself. Every save holds a shared advisory lock from before its first serial until
  # it ends (see `Hologram.DB.Oplog.serial_lock_key/0`), which makes Postgres the keeper of the list
  # of saves still running, also across nodes that don't know of each other, and drops a save from
  # it when its connection dies. So a round notes the highest serial and then the saves running.
  # Once those saves have ended, the serial noted is final: a save starting later takes the lock
  # after the serial was read, so every serial it gets is above it.
  #
  # The limit stops at the last entry the log holds at or below the serial, never at the serial
  # itself. A serial no entry holds belongs to a save that didn't commit, and PostgreSQL doesn't
  # flush a sequence's move until a commit needs it, so a crash can hand that serial out again, to a
  # save that's still running while the limit stands above it. A committed entry's serial is flushed
  # with its commit, so a sequence recovering from a crash always resumes above it.
  #
  # What a round noted says nothing about a later life of the server, where the same serials can
  # go to other saves. So every read of a round names the server's run (see
  # `Hologram.DB.Oplog.serials_in_flight/0`), and a new run drops the rounds waiting. The limit
  # stays, unless the entry it stands on is gone or another one: the server then lost commits, which
  # asynchronous commit and failover to an asynchronous standby can do, and the serials above what
  # it kept will be handed out again.
  #
  # Rounds overlap. Each one waits only for the saves it saw, so one long save holds back the rounds
  # it was part of, while the limit still reaches everything below it as soon as it ends. A save
  # outside the log holds no lock and waits for nothing.

  require Logger

  alias Hologram.DB.Connection
  alias Hologram.DB.Oplog

  # How many rounds wait at once. Past it the newest round gives way to the one replacing it, which
  # only makes the limit reach that serial a little later: a save running for a long time under a
  # steady stream of writes would otherwise queue a round per wake for as long as it runs.
  @max_candidates 64

  @type entry_reader :: (non_neg_integer -> {Oplog.log_entry() | nil, String.t() | nil})

  @type t :: %{
          candidates: list({non_neg_integer, MapSet.t(String.t())}),
          limit: non_neg_integer | nil,
          limit_entry: Oplog.log_entry() | nil,
          losses: non_neg_integer,
          run: String.t() | nil,
          run_key_missing: boolean,
          through: non_neg_integer | nil
        }

  @doc """
  Returns a limit that knows of no serial yet.
  """
  @spec new() :: t
  def new do
    %{
      candidates: [],
      limit: nil,
      limit_entry: nil,
      losses: 0,
      run: nil,
      run_key_missing: false,
      through: nil
    }
  end

  @doc """
  Runs one round against the database, and returns the limit moved as far as the saves that have
  ended allow.

  Raises outside the one thing it can be: a read of the database as it stands. Inside a transaction
  its reads of the log could come from a snapshot older than the saves it saw end.
  """
  @spec advance(t) :: t
  def advance(state) do
    if Connection.in_transaction?() do
      raise ArgumentError, "the final limit can't be worked out inside a transaction"
    end

    case Oplog.serials_in_flight() do
      {_high, _running, nil} ->
        put_run_back(state)

      {high, running, run} ->
        key_present = %{state | run_key_missing: false}

        advance(key_present, run, high, running, &Oplog.last_entry_through/1, &Oplog.entry_at/1)
    end
  rescue
    # A schema-only restore, or one that died before its last step, leaves the view naming the copy
    # of the database empty, and no run can be read until it's filled.
    error in MatchError ->
      case error.term do
        {:error, %Postgrex.Error{postgres: %{code: :object_not_in_prerequisite_state}}} ->
          :ok = Oplog.populate_database_copy()
          state

        _other ->
          reraise error, __STACKTRACE__
      end
  end

  @doc """
  Runs one round given the server run, the highest serial handed out and the saves running when it
  was read, those having been read after it, and what reads the log's last entry at or below a seq
  and its entry at one, each with the run it was read in. The limit moves down only when the server
  lost the entry it stood on.
  """
  @spec advance(
          t,
          String.t(),
          non_neg_integer,
          MapSet.t(String.t()),
          entry_reader,
          entry_reader
        ) :: t
  def advance(state, run, high, running, last_entry_through, entry_at) do
    case enter_run(state, run, entry_at) do
      {:ok, entered} ->
        entered
        |> note(high, running)
        |> settle(running, last_entry_through)

      :run_moved ->
        state
    end
  end

  @doc """
  Returns the saves the waiting rounds wait for, by the virtual transaction ids pg_locks names them
  by.
  """
  @spec holders(t) :: MapSet.t(String.t())
  def holders(state) do
    Enum.reduce(state.candidates, MapSet.new(), fn {_high, holders}, all ->
      MapSet.union(all, holders)
    end)
  end

  @doc """
  Returns the highest serial known to be final, or nil before the first round to finish.
  """
  @spec limit(t) :: non_neg_integer | nil
  def limit(state), do: state.limit

  @doc """
  Returns how many times the limit was found standing on an entry the server lost. Each time, the
  serials above what the server kept go to other saves, and anyone who read past it was told of
  entries that are gone.
  """
  @spec losses(t) :: non_neg_integer
  def losses(state), do: state.losses

  @doc """
  Returns the place of the limit (see `Hologram.DB.Oplog.place/1`), the place of the entry it stands
  on, or nil before the first round to finish.
  """
  @spec place(t) :: Oplog.place() | nil
  def place(%{limit: nil}), do: nil

  def place(state), do: Oplog.place(state.limit_entry)

  @doc """
  Returns the server run the last round counted was read in (see
  `Hologram.DB.Oplog.serials_in_flight/0`), or nil before the first.
  """
  @spec run(t) :: String.t() | nil
  def run(state), do: state.run

  @doc """
  Returns whether a round is waiting for a save to end. A save that rolls back or loses its
  connection announces nothing, so whoever drives the rounds has to look again while this holds.
  """
  @spec waiting?(t) :: boolean
  def waiting?(state), do: state.candidates != []

  defp enter_run(%{run: run} = state, run, _entry_at), do: {:ok, state}

  defp enter_run(%{run: nil} = state, run, _entry_at), do: {:ok, %{state | run: run}}

  defp enter_run(%{limit_entry: nil} = state, run, _entry_at), do: {:ok, new_run(state, run)}

  defp enter_run(%{limit_entry: entry} = state, run, entry_at) do
    case entry_at.(entry.seq) do
      {^entry, ^run} -> {:ok, new_run(state, run)}
      {_other_entry, ^run} -> {:ok, lose_limit(new_run(state, run))}
      {_entry, _other_run} -> :run_moved
    end
  end

  defp lose_limit(state) do
    %{state | limit: nil, limit_entry: nil, losses: state.losses + 1}
  end

  defp new_run(state, run), do: %{state | candidates: [], run: run, through: nil}

  defp note(%{through: through} = state, high, _running)
       when is_integer(through) and high <= through,
       do: state

  defp note(%{candidates: [{newest, _holders} | _older]} = state, high, _running)
       when high <= newest,
       do: state

  defp note(%{candidates: candidates} = state, high, running)
       when length(candidates) >= @max_candidates do
    %{state | candidates: [{high, running} | tl(candidates)]}
  end

  defp note(state, high, running) do
    %{state | candidates: [{high, running} | state.candidates]}
  end

  # A restore passes through a missing key on its way, but a crash during one leaves it missing, and
  # the limit can't move until the restore is run again. Warns once per stretch.
  defp put_run_back(state) do
    case {Oplog.ensure_server_run(), state.run_key_missing} do
      {:ok, _key_missing} ->
        state

      {:no_key, true} ->
        state

      {:no_key, false} ->
        Logger.warning(
          ~s(Hologram: table "server_run" has no primary key, so sync can't confirm new changes. ) <>
            "A database restore adds it when it finishes. If none is running, run the restore again."
        )

        %{state | run_key_missing: true}
    end
  end

  defp raise_limit(state, nil), do: %{state | limit: state.limit || 0}

  defp raise_limit(%{limit: limit} = state, %{seq: seq}) when is_integer(limit) and seq <= limit,
    do: state

  defp raise_limit(state, entry), do: %{state | limit: entry.seq, limit_entry: entry}

  # A round read in another run says nothing, and the next round drops what's waiting.
  defp release(state, candidates, through, last_entry_through) do
    run = state.run

    case last_entry_through.(through) do
      {entry, ^run} ->
        kept = Enum.filter(candidates, fn {high, _holders} -> high > through end)

        raise_limit(%{state | candidates: kept, through: through}, entry)

      {_entry, _other_run} ->
        %{state | candidates: candidates}
    end
  end

  # A round is over once none of the saves it saw are left.
  defp settle(state, running, last_entry_through) do
    candidates =
      Enum.map(state.candidates, fn {high, holders} ->
        {high, MapSet.intersection(holders, running)}
      end)

    case for {high, holders} <- candidates, MapSet.size(holders) == 0, do: high do
      [] -> %{state | candidates: candidates}
      over -> release(state, candidates, Enum.max(over), last_entry_through)
    end
  end
end
