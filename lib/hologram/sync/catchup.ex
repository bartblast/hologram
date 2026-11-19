defmodule Hologram.Sync.Catchup do
  @moduledoc false

  # What a client that comes back missed while it was away - or why it cannot be told, and has to
  # be sent everything again.
  #
  # Replaying the gap costs what CHANGED while the client was away. Sending everything again costs
  # what it HOLDS. A client away for five minutes holding forty rows is told about the two that
  # moved, which is why the gap is the routine and the resync is the fallback.
  #
  # Six doors lead to that fallback, and each is a thing that cannot usefully be answered rather
  # than a thing that went wrong: a place that cannot be read, a place judged under other rules, a
  # place filled with other entity types, a place predating the log, a gap too big to be worth
  # replaying, and a gap spanning a change of model. All of them are decided before a single ROW is
  # looked at - the effects name which rows to read, and none is read here.
  #
  # Rules are a change no gap can hold at all: a deploy that narrows or widens who may read a row
  # moves no row and writes no effect, so what the client holds was decided by rules that no longer
  # apply, and only judging all of it again under the current ones says what it may keep. The place
  # carries the rules it was judged under, which costs a client nothing when they match.
  #
  # A grant given or taken away while the client was gone is a change the gap holds like any other:
  # the backwards search reaches every row it moved (see `Hologram.Sync.Search`), so the session
  # judges those rows as it judges a live batch's.

  alias Hologram.DB.Oplog
  alias Hologram.Entity.Model
  alias Hologram.Sync.Cursor

  # The most effects a replay will carry, and past it the client is sent everything instead.
  #
  # A COUNT is an honest bound here only because the history read leaves a row's payload behind:
  # an effect it returns is 33 words whatever the row was, where one carrying the row's `data` runs
  # from 33 for a delete to 337 for a wide entity's put - a tenfold spread a count cannot see. An
  # edge keeps its payload, a relationship name and an id, at about 60 words whatever the entity.
  # The connection process reads the gap and is killed at a million words, so 5,000 of them is
  # 1.3 MB against a 7 MB cap, under a fifth of it, and a third were every one an edge - neither
  # fraction moves with what the app stores.
  #
  # The economics set the ceiling rather than the memory does, which is why the number is thousands
  # and not tens of thousands: a replay re-reads every row it names, so by a few thousand touched
  # rows it already costs what a resync costs, and unlike a resync it is unbounded. Where between
  # those the line falls is the policy part - the per-effect size and the kill threshold are not.
  @default_gap_limit 5_000

  # How many rows one frame carries. A frame holds whole rows rather than the log's fixed-size
  # entries, so its cost moves with what the app stores - 500 wide rows is megabytes where 500
  # narrow ones is kilobytes, which is why this is smaller than the gap limit by an order of
  # magnitude rather than equal to it. Policy: it trades frames-per-fill against bytes-per-frame,
  # and neither end is dangerous.
  #
  # A catch-up is worked through in chunks of this many effects, each claiming the place of its last
  # one, so a client cut off mid catch-up resumes after the chunks it got.
  @default_rows_per_frame 500

  @doc """
  Returns the most effects a replay will carry.
  """
  @spec gap_limit() :: pos_integer
  def gap_limit do
    :hologram
    |> Application.get_env(:sync, [])
    |> Keyword.get(:gap_limit, @default_gap_limit)
  end

  @doc """
  Returns how many rows one frame carries.

  A frame is built, encoded and written whole, so this is what bounds the memory any single one
  costs - and on a replay it is also the granularity a cut-off client resumes at.
  """
  @spec rows_per_frame() :: pos_integer
  def rows_per_frame do
    :hologram
    |> Application.get_env(:sync, [])
    |> Keyword.get(:rows_per_frame, @default_rows_per_frame)
  end

  @doc """
  Returns the effects written since the given cursor, without their payloads (see
  `Hologram.DB.Oplog.read_after/3`), and the edge below which every transaction had finished
  before they were read (see `Hologram.DB.Oplog.current_xmin/0`) - or why everything must be sent
  again: a cursor judged under rules other than the given policy hash's (see
  `Hologram.Policy.hash/0`), and one filled with entity types other than the given types hash's (see
  `Hologram.Sync.Cursor.types_hash/2`), among the reasons.

  What comes back names WHICH rows moved, never what they now hold - the values come from reading
  those rows as they stand. That is what makes the log safe to read as history: its order is not
  commit order, so folding it would build a past that never happened, while using it as an index
  of ids cannot.

  The edge is what a place the catch-up hands over may reach. The log's order is by transaction id,
  not by commit, so a transaction below an effect the read returned can still have been open then,
  and commit after: a place past it would have a client cut off right then come back past changes
  it never got. Every effect of a transaction below the edge is among the ones returned.
  """
  @spec gap(term, String.t() | nil, String.t(), String.t()) ::
          {:ok, list(map), non_neg_integer} | {:full_resync, atom}
  def gap(cursor, _actor_user_id, policy_hash, types_hash) do
    with {:ok, tx, seq, cursor_policy_hash, cursor_types_hash} <- decode_place(cursor),
         :ok <- check_rules(cursor_policy_hash, policy_hash),
         :ok <- check_types(cursor_types_hash, types_hash),
         :ok <- check_retention(tx, seq) do
      read_gap(tx, seq)
    end
  end

  # The edge is read first: a transaction it counts as finished had finished before the effects were
  # read, so the read holds what it wrote.
  defp read_gap(tx, seq) do
    edge = Oplog.current_xmin()

    effects = Oplog.read_after(tx, seq, gap_limit() + 1)

    with {:ok, effects} <- check_size(effects) do
      {:ok, effects, edge}
    end
  end

  # Read one past the limit, so "too many" is answered without holding them all: the extra row is
  # the only evidence needed that the gap does not fit.
  defp check_size(effects) do
    if length(effects) > gap_limit() do
      {:full_resync, :gap_too_large}
    else
      check_model(effects)
    end
  end

  # A gap spanning a deploy is refused whole rather than in part: the client's bundle reads rows of
  # one model, and half a replay would hand it rows of two.
  defp check_model(effects) do
    model_hash = Model.hash()

    if Enum.all?(effects, &(&1.model_hash == model_hash)) do
      {:ok, effects}
    else
      {:full_resync, :model_hash}
    end
  end

  # A client judged under other rules is sent everything again like any other resync, so the rows
  # it holds stay on screen until the marker ending the refill takes away the ones the current
  # rules hide - not dropped at once, as for a change of identity. Those rows were the client's to
  # see a moment ago and are already on the device, so hiding them before the refill lands
  # protects nothing, and it would empty every returning client's pages on every deploy that
  # touches a rule. It is the same window a grant revoked under a connected client has, until the
  # round that takes its rows away.
  defp check_rules(policy_hash, policy_hash), do: :ok

  defp check_rules(_cursor_policy_hash, _policy_hash), do: {:full_resync, :policy_hash}

  # A client filled before a deploy changed which types sync sends holds none of a type added since,
  # and nothing in the log says so - the rows were always there, the client was just never sent
  # them. Only filling it again does.
  defp check_types(types_hash, types_hash), do: :ok

  defp check_types(_cursor_types_hash, _types_hash), do: {:full_resync, :synced_types}

  # The cursor came from a frame, so the effect it names was written. If the oldest effect still
  # held is NEWER than that, the cursor predates the log and what it names cannot be told. If the
  # oldest is at or below it, the log speaks for the whole gap.
  #
  # A log holding nothing cannot say either way, so it says the honest thing.
  defp check_retention(tx, seq) do
    case Oplog.oldest_place() do
      nil -> {:full_resync, :retention}
      oldest when oldest <= {tx, seq} -> :ok
      _predates_log -> {:full_resync, :retention}
    end
  end

  defp decode_place(cursor) do
    case Cursor.decode(cursor) do
      {:ok, tx, seq, policy_hash, types_hash} -> {:ok, tx, seq, policy_hash, types_hash}
      :error -> {:full_resync, :cursor}
    end
  end
end
