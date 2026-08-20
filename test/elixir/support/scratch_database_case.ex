defmodule Hologram.Test.ScratchDatabaseCase do
  @moduledoc false

  # Case template for tests that need a real database: writes that commit, sessions that
  # see each other's work, and statements that refuse to run inside a transaction. The
  # sandboxed DatabaseCase wraps each test in one never-committed transaction, which puts
  # all three structurally out of its reach. Every test here gets a database of its own,
  # created from template0 before it runs and dropped after it, so "virgin" and "absent"
  # are literally true and nothing a test leaves behind - a session lock held by a dead
  # actor, a half-built index, a straggler session - reaches the next test.
  #
  # The gateway is pointed at the scratch database with route/2: the migrator and the
  # gateway keep calling Connection.query/transaction and follow the routing. Nothing
  # here checks out a pool connection, so a gateway call made outside route/2 reaches the
  # suite-wide ownership pool without an owner and fails. Further sessions are raw
  # Postgrex connections started from :scratch_opts.
  #
  # The maintenance connection lives only as long as the statement it carries: one is
  # opened for the CREATE DATABASE and another for the DROP DATABASE, which runs in the
  # on_exit process after the scratch connection is gone (the test supervisor's children
  # terminate before on_exit callbacks run). WITH (FORCE) ends the sessions a test's
  # actors leave behind.

  use ExUnit.CaseTemplate

  alias Hologram.DB.Config
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper

  using do
    quote do
      import Hologram.Commons.TestUtils
      import Hologram.Test.Helpers
      import Hologram.Test.ScratchDatabaseCase

      @moduletag :scratch_database
    end
  end

  setup do
    database = "hologram_scratch_#{System.unique_integer([:positive])}"
    quoted_database = Mapper.quote_identifier(database)

    with_maintenance_connection(fn connection ->
      Postgrex.query!(connection, "CREATE DATABASE #{quoted_database} TEMPLATE template0", [])
    end)

    on_exit(fn ->
      with_maintenance_connection(fn connection ->
        Postgrex.query!(connection, "DROP DATABASE #{quoted_database} WITH (FORCE)", [])
      end)
    end)

    scratch_opts = Config.connection_opts(database: database)
    scratch = start_supervised!({Postgrex, scratch_opts})

    [scratch: scratch, scratch_opts: scratch_opts]
  end

  @doc """
  Runs the given function with the calling process's queries and transactions routed to
  the given scratch connection.
  """
  @spec route(GenServer.server(), (-> any)) :: any
  def route(scratch, fun), do: Connection.with_connection(scratch, fun)

  defp with_maintenance_connection(fun) do
    connection_opts = Config.connection_opts([])
    {:ok, connection} = Postgrex.start_link(connection_opts)

    try do
      fun.(connection)
    after
      GenServer.stop(connection)
    end
  end
end
