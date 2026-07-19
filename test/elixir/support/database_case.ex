defmodule Hologram.Test.DatabaseCase do
  @moduledoc false

  # Case template for tests that touch the database. A dedicated owner process checks out
  # a connection from the suite-wide ownership pool, opens a transaction that is never
  # committed, and allows the test process to use its connection - so every write a test
  # makes stays uncommitted. After the test process exits, on_exit tells the owner to roll
  # the transaction back and check the connection in clean. Safe under async: true, because
  # uncommitted writes are invisible to the connections of other test processes.
  #
  # The owner must be a separate process that outlives the test process: a connection
  # checked in by an exiting owner returns to the pool with its transaction still open,
  # and nothing rolls it back until an ownership timeout disconnects it.

  use ExUnit.CaseTemplate

  alias Hologram.Database

  using do
    quote do
      import Hologram.Commons.TestUtils
      import Hologram.Test.Helpers

      @fixtures_dir Path.join([File.cwd!(), "test", "elixir", "support", "fixtures"])
    end
  end

  setup do
    pool_name = Database.pool_name()
    test_pid = self()
    setup_pid = self()

    owner_pid =
      spawn(fn ->
        :ok = DBConnection.Ownership.ownership_checkout(pool_name, [])
        Postgrex.query!(pool_name, "BEGIN", [])
        :ok = DBConnection.Ownership.ownership_allow(pool_name, self(), test_pid, [])
        send(setup_pid, {:sandbox_ready, self()})

        receive do
          {:rollback, caller_pid} ->
            Postgrex.query!(pool_name, "ROLLBACK", [])
            :ok = DBConnection.Ownership.ownership_checkin(pool_name, [])
            send(caller_pid, {:sandbox_finished, self()})
        end
      end)

    receive do
      {:sandbox_ready, ^owner_pid} -> :ok
    end

    # Route the gateway's transaction machinery through the sandbox: transaction/2
    # emulates the outermost transaction with a savepoint instead of BEGIN/COMMIT.
    Database.enter_sandbox()

    on_exit(fn ->
      send(owner_pid, {:rollback, self()})

      receive do
        {:sandbox_finished, ^owner_pid} -> :ok
      end
    end)

    :ok
  end
end
