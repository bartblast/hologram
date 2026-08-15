defmodule Hologram.Sync.DispatcherTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Sync.Dispatcher

  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.Test.Fixtures.Entity.Module2

  @entity_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e0f"

  defp seed(tx, entity_id) do
    statement = """
    INSERT INTO "hologram_system"."outbox" ("op", "type", "entity_id", "tx", "model_hash")
    VALUES ('del_entity', 'Hologram.Test.Fixtures.Entity.Module2', $1, $2, 'seeded')
    """

    {:ok, _result} = Connection.query(statement, [Codec.encode(entity_id, :uuid), tx])

    :ok
  end

  # The dispatcher reads from its own process, which the sandbox owner must let in - otherwise it
  # would reach the pool rather than the transaction this test is writing into.
  defp start_dispatcher!(opts) do
    test_pid = self()
    handler = fn transactions -> send(test_pid, {:dispatched, transactions}) end

    pid = start_supervised!({Hologram.Sync.Dispatcher, Keyword.put_new(opts, :handler, handler)})

    :ok = DBConnection.Ownership.ownership_allow(DB.pool_name(), self(), pid, [])

    pid
  end

  describe "start_link/1" do
    test "starts reading at the log's current edge when given no cursor" do
      seed(200, @entity_id)

      dispatcher = start_dispatcher!([])

      wake(dispatcher)

      refute_receive {:dispatched, _transactions}, 100
    end

    test "refuses to start with nowhere to send what it reads" do
      assert_raise KeyError, fn -> init([]) end
    end
  end

  describe "handle :wake" do
    test "hands over the transactions the window holds" do
      seed(200, @entity_id)

      dispatcher = start_dispatcher!(cursor: 200)

      wake(dispatcher)

      assert_receive {:dispatched, [{200, [event]}]}
      assert event.op == :del_entity
      assert event.type == Module2
      assert event.entity_id == @entity_id
    end

    test "hands over nothing when the window is empty" do
      dispatcher = start_dispatcher!(cursor: 200)

      wake(dispatcher)

      refute_receive {:dispatched, _transactions}, 100
    end

    test "moves past what it handed over, so a second wake repeats nothing" do
      seed(200, @entity_id)

      dispatcher = start_dispatcher!(cursor: 200)

      wake(dispatcher)
      assert_receive {:dispatched, [{200, _events}]}

      wake(dispatcher)

      refute_receive {:dispatched, _transactions}, 100
    end

    # Whether draining the mailbox happens before or after the window is read cannot be told
    # apart here: the sandbox runs the test inside one transaction, so the dispatcher's edge
    # never reaches the rows this test writes, and every round after the first reads nothing
    # whichever way it drains. Commit 24's feature test, where transactions really commit while
    # a dispatcher is working, is where the placement is proven.
    test "keeps reading after a wake that arrives with nothing behind it" do
      seed(200, @entity_id)

      dispatcher = start_dispatcher!(cursor: 200)

      wake(dispatcher)
      assert_receive {:dispatched, [{200, _events}]}

      wake(dispatcher)
      wake(dispatcher)

      assert Process.alive?(dispatcher)
      refute_receive {:dispatched, _transactions}, 100
    end
  end
end
