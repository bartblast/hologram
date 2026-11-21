defmodule Hologram.Sync.Pool do
  @moduledoc false

  # The database connections sync's own heavy reads go through: a first arrival's fill and a
  # returning client's catch-up. A wave of clients coming back after a deploy is all of those at
  # once, and on the app's own pool it would leave the app's requests queueing behind them. On a
  # pool of its own the wave queues behind itself, and the app's requests go on being answered.
  # What keeps a connected client current stays on the app's pool - the dispatcher's per-batch
  # reads, and a type read again whole for a grant that moved under a connected client - since a
  # wave must not hold that up either.
  #
  # Its size defaults to how many catch-ups run at once (see `Hologram.Sync.Gate`), so each has a
  # connection. Fills aren't let in by turn, so they queue here for one - which is why a wait here
  # isn't an error for minutes, where the app's pool gives up on one within seconds: a fill waiting
  # its turn for a connection is the pool doing its job, and one given up on is a client sent back
  # to fill again, which makes the wave longer.

  alias Hologram.DB
  alias Hologram.DB.Config
  alias Hologram.DB.Connection
  alias Hologram.DB.Protocol
  alias Hologram.Sync.Gate

  @name __MODULE__

  # DBConnection drops a checkout once checkouts have waited longer than the target for a whole
  # interval, which the app's pool keeps short so a request fails fast. A drop is an error the
  # caller is answered with, and the connections are left alone.
  @queue_interval_ms :timer.minutes(1)

  @queue_target_ms :timer.minutes(1)

  # The driver's timeout counts the wait for a connection as well as the run, and a connection
  # handed over past its deadline is closed at once. A waiter can be handed one up to about the
  # target plus two intervals after it asked, so the timeout is that plus a minute for the run - no
  # wait the queue allows closes a connection, and a socket that went silent, a database host gone
  # without a word, is closed within minutes rather than held for good.
  @timeout_ms @queue_target_ms + 2 * @queue_interval_ms + :timer.minutes(1)

  @doc """
  Returns the child spec of the pool, or nil when the configured size is 0 and none is started.
  """
  @spec child_spec(keyword) :: Supervisor.child_spec() | nil
  def child_spec(_opts \\ []) do
    case size() do
      0 ->
        nil

      size ->
        [
          after_connect: {DB, :apply_session_settings, []},
          name: @name,
          parameters: [application_name: "hologram_sync"],
          pool_size: size,
          queue_interval: @queue_interval_ms,
          queue_target: @queue_target_ms
        ]
        |> Config.connection_opts()
        |> Protocol.child_spec()
        |> Map.put(:id, @name)
    end
  end

  @doc """
  Returns the name the pool is started under.
  """
  @spec name() :: atom
  def name, do: @name

  @doc """
  Runs the given function with the calling process's queries routed to the pool when it is
  started (see `Hologram.DB.Connection.with_connection/2`), each with a driver timeout long enough
  to wait as long as the pool's queue allows (see `Hologram.DB.Connection.with_timeout/2`), and on
  whatever they already went through otherwise - the app's pool, or a test's sandbox.
  """
  @spec run((-> result)) :: result when result: any
  def run(fun) do
    if Process.whereis(@name) do
      Connection.with_connection(@name, fn -> Connection.with_timeout(@timeout_ms, fun) end)
    else
      fun.()
    end
  end

  @doc """
  Returns how many connections the pool opens: the `:pool_size` key of the `:sync` config,
  defaulting to how many catch-ups a node runs at once, 4 (see
  `Hologram.Sync.Gate.catchups_at_once/0`). 0 starts none, and sync's reads share the app's pool.
  Anything but a non-negative integer raises.
  """
  @spec size() :: non_neg_integer
  def size do
    configured =
      :hologram
      |> Application.get_env(:sync, [])
      |> Keyword.get(:pool_size)

    case configured do
      nil ->
        Gate.catchups_at_once()

      size when is_integer(size) and size >= 0 ->
        size

      other ->
        raise ArgumentError,
              "config :hologram, :sync, pool_size: expects a non-negative integer, " <>
                "got: #{inspect(other)}"
    end
  end
end
