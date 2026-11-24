defmodule Hologram.DB.ConnectionTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.DB.Connection

  alias Ecto.Adapters.SQL.Sandbox
  alias Hologram.DB
  alias Hologram.DB.Config
  alias Hologram.MisuseError
  alias Hologram.Test.EctoRepo

  # Reaches the server outside the sandbox: this is the transaction machinery the sandbox
  # routes through, so it is tested on a real connection.
  @moduletag :database

  # Stand-ins for the errors PostgreSQL raises, carrying the fields Postgrex.Error renders - a real
  # deadlock needs two sessions crossing, which the scratch tier stages.
  @deadlock_error %Postgrex.Error{
    postgres: %{
      code: :deadlock_detected,
      message: "deadlock detected",
      pg_code: "40P01",
      severity: "ERROR"
    }
  }

  @insert_given_id_sql ~s|INSERT INTO "hologram_data"."test_fixtures_entity_module1" ("id", "created_at", "server_created_at", "server_updated_at", "updated_at", "$revisions") VALUES ($1, now(), now(), now(), now(), '{}')|

  @insert_returning_id_sql ~s|INSERT INTO "hologram_data"."test_fixtures_entity_module1" ("id", "created_at", "server_created_at", "server_updated_at", "updated_at", "$revisions") VALUES (gen_random_uuid(), now(), now(), now(), now(), '{}') RETURNING "id"|

  @unique_violation_error %Postgrex.Error{
    postgres: %{
      code: :unique_violation,
      message: "duplicate key value violates unique constraint",
      pg_code: "23505",
      severity: "ERROR"
    }
  }

  defp count_by_id(id) do
    count_sql =
      ~s|SELECT count(*) FROM "hologram_data"."test_fixtures_entity_module1" WHERE "id" = $1|

    {:ok, %Postgrex.Result{rows: [[count]]}} = query(count_sql, [id])
    count
  end

  # Counts a run of the function under test and returns which run this is.
  defp count_run(runs) do
    Agent.get_and_update(runs, &{&1 + 1, &1 + 1})
  end

  defp delete_by_id(id) do
    delete_sql = ~s|DELETE FROM "hologram_data"."test_fixtures_entity_module1" WHERE "id" = $1|

    {:ok, _result} = query(delete_sql, [id])
    :ok
  end

  describe "in_transaction?/0" do
    test "is false outside a transaction" do
      refute in_transaction?()
    end

    test "is true inside a transaction" do
      assert transaction(fn -> in_transaction?() end) == {:ok, true}
    end

    test "is true inside a nested transaction" do
      assert transaction(fn -> transaction(fn -> in_transaction?() end) end) == {:ok, {:ok, true}}
    end

    test "is false in the sandbox outside a transaction" do
      task =
        Task.async(fn ->
          enter_sandbox()
          in_transaction?()
        end)

      refute Task.await(task)
    end

    test "is false on another connection routed from inside a transaction" do
      {:ok, connection} = Postgrex.start_link(Config.connection_opts())

      assert transaction(fn ->
               with_connection(connection, fn -> in_transaction?() end)
             end) == {:ok, false}

      GenServer.stop(connection)
    end
  end

  describe "inside an Ecto transaction" do
    setup do
      [repo_pid: EctoRepo.start_for_test!()]
    end

    defp assert_refused(fun) do
      assert {:ok, :refused} =
               EctoRepo.transaction(fn ->
                 assert_raise MisuseError, ~r/inside a Hologram\.Test\.EctoRepo transaction/, fun

                 :refused
               end)
    end

    test "execute/3 is refused" do
      {:ok, prepared} = prepare("SELECT 1")

      assert_refused(fn -> execute(prepared, []) end)
    end

    test "prepare/2 is refused" do
      assert_refused(fn -> prepare("SELECT 1") end)
    end

    test "query/3 is refused" do
      assert_refused(fn -> query("SELECT 1") end)
    end

    test "retry_on_deadlock/1 is refused without running the function" do
      assert_refused(fn -> retry_on_deadlock(fn -> flunk("the function ran") end) end)
    end

    test "snapshot/1 is refused without running the function" do
      assert_refused(fn -> snapshot(fn -> flunk("the function ran") end) end)
    end

    test "transaction/2 is refused without running the function" do
      assert_refused(fn -> transaction(fn -> flunk("the function ran") end) end)
    end

    test "a refused write leaves no row" do
      id = :crypto.strong_rand_bytes(16)

      assert_refused(fn -> query(@insert_given_id_sql, [id]) end)

      assert count_by_id(id) == 0
    end

    test "a call works again once the Ecto transaction has ended" do
      {:ok, :done} = EctoRepo.transaction(fn -> :done end)

      assert {:ok, %Postgrex.Result{rows: [[1]]}} = query("SELECT 1")
    end

    test "a call under Hologram's sandbox with no transaction of its own isn't refused" do
      task =
        Task.async(fn ->
          enter_sandbox()
          query("SELECT 1")
        end)

      assert {:ok, %Postgrex.Result{rows: [[1]]}} = Task.await(task)
    end

    test "a call under Ecto's SQL sandbox with no transaction of its own isn't refused", %{
      repo_pid: repo_pid
    } do
      :ok = Sandbox.checkout(repo_pid)

      assert {:ok, %Postgrex.Result{rows: [[1]]}} = query("SELECT 1")
    end
  end

  describe "query/3" do
    test "executes the statement with the given params" do
      assert {:ok, %Postgrex.Result{rows: [[42]]}} = query("SELECT $1::int8 + 1", [41])
    end

    test "returns errors as tagged tuples" do
      assert {:error, %Postgrex.Error{}} = query("SELECT * FROM nonexistent_table")
    end
  end

  describe "record_ecto_call/2" do
    @ecto_call_msg "SomeRepo ran \"INSERT INTO audit\" inside a data layer transaction - Ecto commits on a connection of its own, so anything it wrote may already be committed while this transaction rolls back. Run Ecto calls before or after the transaction."

    # A transaction the way the test sandbox holds one: opened outside the code under test, with
    # the code's outermost transaction emulated by a savepoint.
    defp in_sandbox(fun) do
      task =
        Task.async(fn ->
          pool_name = DB.pool_name()
          Postgrex.query!(pool_name, "BEGIN", [])
          enter_sandbox()

          try do
            fun.()
          after
            Postgrex.query!(pool_name, "ROLLBACK", [])
          end
        end)

      Task.await(task)
    end

    defp insert_row do
      id = :crypto.strong_rand_bytes(16)
      {:ok, _result} = query(@insert_given_id_sql, [id])

      id
    end

    # A rollback that goes ahead throws, which an assertion on what it raises can't see, and the
    # end of the transaction then raises the same error.
    defp refused_rollback do
      rollback(:some_reason)
    catch
      :throw, _value -> flunk("the rollback went ahead")
    end

    test "fails the transaction at its next statement and rolls its writes back" do
      id = :crypto.strong_rand_bytes(16)

      assert_error MisuseError, @ecto_call_msg, fn ->
        transaction(fn ->
          {:ok, _result} = query(@insert_given_id_sql, [id])
          record_ecto_call(SomeRepo, "INSERT INTO audit")
          query("SELECT 1")
          flunk("the statement ran")
        end)
      end

      assert count_by_id(id) == 0
    end

    test "fails the transaction at the end of its block and rolls its writes back" do
      id = :crypto.strong_rand_bytes(16)

      assert_error MisuseError, @ecto_call_msg, fn ->
        transaction(fn ->
          {:ok, _result} = query(@insert_given_id_sql, [id])
          record_ecto_call(SomeRepo, "INSERT INTO audit")
        end)
      end

      assert count_by_id(id) == 0
    end

    test "fails the emulated transaction of the test sandbox and rolls its writes back" do
      in_sandbox(fn ->
        id = :crypto.strong_rand_bytes(16)

        assert_error MisuseError, @ecto_call_msg, fn ->
          transaction(fn ->
            {:ok, _result} = query(@insert_given_id_sql, [id])
            record_ecto_call(SomeRepo, "INSERT INTO audit")
          end)
        end

        assert count_by_id(id) == 0
        assert transaction(fn -> :ok end) == {:ok, :ok}
      end)
    end

    test "still fails the transaction when the caller rescues the first raise" do
      id = :crypto.strong_rand_bytes(16)

      assert_error MisuseError, @ecto_call_msg, fn ->
        transaction(fn ->
          {:ok, _result} = query(@insert_given_id_sql, [id])
          record_ecto_call(SomeRepo, "INSERT INTO audit")

          assert_error MisuseError, @ecto_call_msg, fn -> query("SELECT 1") end
        end)
      end

      assert count_by_id(id) == 0
    end

    test "still fails the outermost block when the caller rescues a nested block's raise" do
      id = :crypto.strong_rand_bytes(16)

      assert_error MisuseError, @ecto_call_msg, fn ->
        transaction(fn ->
          {:ok, _result} = query(@insert_given_id_sql, [id])

          assert_error MisuseError, @ecto_call_msg, fn ->
            transaction(fn -> record_ecto_call(SomeRepo, "INSERT INTO audit") end)
          end
        end)
      end

      assert count_by_id(id) == 0
    end

    test "makes rollback/1 raise rather than return the reason" do
      id = :crypto.strong_rand_bytes(16)

      assert_error MisuseError, @ecto_call_msg, fn ->
        transaction(fn ->
          {:ok, _result} = query(@insert_given_id_sql, [id])
          record_ecto_call(SomeRepo, "INSERT INTO audit")
          refused_rollback()
        end)
      end

      assert count_by_id(id) == 0
    end

    test "leaves an exception the block raises itself as it is" do
      assert_error RuntimeError, "raised by the block", fn ->
        transaction(fn ->
          record_ecto_call(SomeRepo, "INSERT INTO audit")
          raise "raised by the block"
        end)
      end
    end

    test "fails the test sandbox's emulated transaction at its next statement" do
      in_sandbox(fn ->
        id = :crypto.strong_rand_bytes(16)

        assert_error MisuseError, @ecto_call_msg, fn ->
          transaction(fn ->
            {:ok, _result} = query(@insert_given_id_sql, [id])
            record_ecto_call(SomeRepo, "INSERT INTO audit")
            query("SELECT 1")
            flunk("the statement ran")
          end)
        end

        assert count_by_id(id) == 0
      end)
    end

    test "refuses every kind of data layer call that follows it" do
      {:ok, prepared} = prepare("SELECT 1")

      calls = [
        fn -> execute(prepared, []) end,
        fn -> prepare("SELECT 1") end,
        fn -> query("SELECT 1") end,
        fn -> retry_on_deadlock(fn -> flunk("the function ran") end) end,
        fn -> snapshot(fn -> flunk("the function ran") end) end,
        fn -> transaction(fn -> flunk("the function ran") end) end
      ]

      Enum.each(calls, fn call ->
        assert_error MisuseError, @ecto_call_msg, fn ->
          transaction(fn ->
            record_ecto_call(SomeRepo, "INSERT INTO audit")

            assert_error MisuseError, @ecto_call_msg, fn -> call.() end
          end)
        end
      end)
    end

    test "reports a call made while a rollback unwinds the block" do
      assert_error MisuseError, @ecto_call_msg, fn ->
        transaction(fn ->
          try do
            rollback(:some_reason)
          after
            record_ecto_call(SomeRepo, "INSERT INTO audit")
          end
        end)
      end

      assert transaction(fn -> :ok end) == {:ok, :ok}
    end

    test "reports a call made while a rollback unwinds the test sandbox's transaction" do
      in_sandbox(fn ->
        assert_error MisuseError, @ecto_call_msg, fn ->
          transaction(fn ->
            try do
              rollback(:some_reason)
            after
              record_ecto_call(SomeRepo, "INSERT INTO audit")
            end
          end)
        end

        assert transaction(fn -> :ok end) == {:ok, :ok}
      end)
    end

    test "names the statement rather than the begin before it" do
      assert_error MisuseError, @ecto_call_msg, fn ->
        transaction(fn ->
          record_ecto_call(SomeRepo, "begin")
          record_ecto_call(SomeRepo, "INSERT INTO audit")
          record_ecto_call(SomeRepo, "commit")
        end)
      end
    end

    test "names the begin of an Ecto transaction that ran no statement" do
      assert_error MisuseError, ~r/^SomeRepo ran "begin" inside/, fn ->
        transaction(fn ->
          record_ecto_call(SomeRepo, "begin")
          record_ecto_call(SomeRepo, "commit")
        end)
      end
    end

    test "a call inside an Ecto transaction opened in the block is told to move out of it" do
      EctoRepo.start_for_test!()

      assert_error MisuseError, ~r/^Hologram\.Test\.EctoRepo ran "begin" inside/, fn ->
        transaction(fn ->
          record_ecto_call(EctoRepo, "begin")

          EctoRepo.transaction(fn ->
            assert_error MisuseError, ~r/^cannot run a data layer statement inside a/, fn ->
              query("SELECT 1")
            end
          end)
        end)
      end
    end

    test "a rollback inside an Ecto transaction opened in the block is told to move out of it" do
      EctoRepo.start_for_test!()

      assert_error MisuseError, ~r/^Hologram\.Test\.EctoRepo ran "begin" inside/, fn ->
        transaction(fn ->
          record_ecto_call(EctoRepo, "begin")

          EctoRepo.transaction(fn ->
            assert_error MisuseError, ~r/^cannot run a data layer statement inside a/, fn ->
              refused_rollback()
            end
          end)
        end)
      end
    end

    test "names the first call" do
      assert_error MisuseError, @ecto_call_msg, fn ->
        transaction(fn ->
          record_ecto_call(SomeRepo, "INSERT INTO audit")
          record_ecto_call(OtherRepo, "DELETE FROM audit")
        end)
      end
    end

    test "shows the first 200 characters of the statement" do
      statement = String.duplicate("a", 201)
      shown = String.duplicate("a", 200)

      assert_error MisuseError, ~r/^SomeRepo ran "#{shown}" inside/, fn ->
        transaction(fn -> record_ecto_call(SomeRepo, statement) end)
      end
    end

    test "says a query when the statement is unknown" do
      assert_error MisuseError, ~r/^SomeRepo ran a query inside/, fn ->
        transaction(fn -> record_ecto_call(SomeRepo, nil) end)
      end
    end

    test "doesn't carry over into the next transaction" do
      assert_error MisuseError, @ecto_call_msg, fn ->
        transaction(fn -> record_ecto_call(SomeRepo, "INSERT INTO audit") end)
      end

      assert transaction(fn -> :ok end) == {:ok, :ok}
    end

    test "doesn't carry over after the block raised on its own" do
      assert_error RuntimeError, "raised by the block", fn ->
        transaction(fn ->
          record_ecto_call(SomeRepo, "INSERT INTO audit")
          raise "raised by the block"
        end)
      end

      assert transaction(fn -> :ok end) == {:ok, :ok}
    end

    test "records nothing outside a transaction" do
      assert record_ecto_call(SomeRepo, "INSERT INTO audit") == :ok

      assert {:ok, %Postgrex.Result{rows: [[1]]}} = query("SELECT 1")
      assert transaction(fn -> :ok end) == {:ok, :ok}
    end

    test "records nothing in the test sandbox outside a transaction" do
      in_sandbox(fn ->
        assert record_ecto_call(SomeRepo, "INSERT INTO audit") == :ok

        id = insert_row()

        assert count_by_id(id) == 1
        assert transaction(fn -> :ok end) == {:ok, :ok}
      end)
    end

    test "with_connection/2 keeps the outer transaction's record" do
      {:ok, connection} = Postgrex.start_link(Config.connection_opts())

      assert_error MisuseError, @ecto_call_msg, fn ->
        transaction(fn ->
          record_ecto_call(SomeRepo, "INSERT INTO audit")

          {:ok, :ok} = with_connection(connection, fn -> transaction(fn -> :ok end) end)
        end)
      end

      GenServer.stop(connection)
    end

    test "with_connection/2 keeps an inner transaction's record from reaching the outer one" do
      {:ok, connection} = Postgrex.start_link(Config.connection_opts())

      assert {:ok, :rescued} =
               transaction(fn ->
                 with_connection(connection, fn ->
                   try do
                     transaction(fn -> record_ecto_call(SomeRepo, "INSERT INTO audit") end)
                   rescue
                     MisuseError -> :rescued
                   end
                 end)
               end)

      GenServer.stop(connection)
    end
  end

  describe "retry_on_deadlock/1" do
    test "reruns the transaction it opened when PostgreSQL aborts it as a deadlock victim" do
      {:ok, runs} = Agent.start_link(fn -> 0 end)

      result =
        retry_on_deadlock(fn ->
          case count_run(runs) do
            1 -> raise @deadlock_error
            _run -> :landed
          end
        end)

      assert result == {:ok, :landed}
      assert Agent.get(runs, & &1) == 2
    end

    test "commits what the rerun wrote and nothing of the aborted run" do
      {:ok, runs} = Agent.start_link(fn -> 0 end)
      {:ok, inserted_ids} = Agent.start_link(fn -> [] end)

      result =
        retry_on_deadlock(fn ->
          {:ok, %Postgrex.Result{rows: [[id]]}} = query(@insert_returning_id_sql)
          Agent.update(inserted_ids, &[id | &1])

          if count_run(runs) == 1 do
            raise @deadlock_error
          end

          :landed
        end)

      [rerun_id, aborted_id] = Agent.get(inserted_ids, & &1)

      assert result == {:ok, :landed}
      assert count_by_id(aborted_id) == 0
      assert count_by_id(rerun_id) == 1

      delete_by_id(rerun_id)
    end

    test "answers a rollback the way transaction/2 does" do
      assert retry_on_deadlock(fn -> rollback(:some_reason) end) == {:error, :some_reason}
    end

    test "does not rerun inside an enclosing transaction" do
      {:ok, runs} = Agent.start_link(fn -> 0 end)

      assert_error Postgrex.Error, "ERROR 40P01 (deadlock_detected) deadlock detected", fn ->
        transaction(fn ->
          retry_on_deadlock(fn ->
            case count_run(runs) do
              1 -> raise @deadlock_error
              _run -> :landed
            end
          end)
        end)
      end

      assert Agent.get(runs, & &1) == 1
    end

    test "reraises any other database error" do
      {:ok, runs} = Agent.start_link(fn -> 0 end)

      expected_msg =
        "ERROR 23505 (unique_violation) duplicate key value violates unique constraint"

      assert_error Postgrex.Error, expected_msg, fn ->
        retry_on_deadlock(fn ->
          case count_run(runs) do
            1 -> raise @unique_violation_error
            _run -> :landed
          end
        end)
      end

      assert Agent.get(runs, & &1) == 1
    end
  end

  describe "rollback/1" do
    test "makes the innermost enclosing transaction return the reason" do
      assert transaction(fn -> rollback(:some_reason) end) == {:error, :some_reason}
    end

    test "raises outside of a transaction" do
      assert_error MisuseError, "cannot rollback - not inside a transaction", fn ->
        rollback(:some_reason)
      end
    end
  end

  describe "snapshot/1" do
    defp setting(name) do
      {:ok, %Postgrex.Result{rows: [[value]]}} = query("SHOW #{name}")

      value
    end

    test "runs the function in a read-only repeatable read transaction" do
      assert snapshot(fn ->
               {setting("transaction_isolation"), setting("transaction_read_only")}
             end) ==
               {:ok, {"repeatable read", "on"}}
    end

    test "reads every statement from the snapshot its first one took" do
      {:ok, %Postgrex.Result{rows: [[id]]}} = query(@insert_returning_id_sql)

      {:ok, counts} =
        snapshot(fn ->
          before = count_by_id(id)

          # On a connection of its own, so the delete commits outside the snapshot.
          fn -> delete_by_id(id) end
          |> Task.async()
          |> Task.await()

          {before, count_by_id(id)}
        end)

      assert counts == {1, 1}
      assert count_by_id(id) == 0
    end

    # The isolation of a transaction can be set only before its first statement, and an enclosing
    # transaction may have run any number of them, so the snapshot reads at the enclosing one's.
    test "runs the function as a savepoint inside an enclosing transaction" do
      result =
        transaction(fn ->
          snapshot(fn -> setting("transaction_isolation") end)
        end)

      assert result == {:ok, {:ok, "read committed"}}
    end
  end

  describe "transaction/2" do
    test "commits on success and returns the function result" do
      {:ok, inserted_id} =
        transaction(fn ->
          {:ok, %Postgrex.Result{rows: [[id]]}} = query(@insert_returning_id_sql)
          id
        end)

      assert count_by_id(inserted_id) == 1

      delete_by_id(inserted_id)
    end

    test "keeps the enclosing transaction usable after a nested statement fails" do
      result =
        transaction(fn ->
          {:ok, %Postgrex.Result{rows: [[id]]}} = query(@insert_returning_id_sql)
          Process.put(:outer_id, id)

          transaction(fn ->
            {:error, %Postgrex.Error{}} = query(@insert_given_id_sql, [id])
            rollback(:refused)
          end)

          {:ok, _result} = query("SELECT 1")

          :usable
        end)

      outer_id = Process.get(:outer_id)

      assert result == {:ok, :usable}
      assert count_by_id(outer_id) == 1

      delete_by_id(outer_id)
    end

    # The probe runs one level down and its result travels out through rollback/1: a
    # savepoint that is gone cannot be released, and the refusal aborts the transaction
    # until the enclosing level rolls its own savepoint back.
    test "releases a nested transaction's savepoint when it raises" do
      result =
        transaction(fn ->
          transaction(fn ->
            Enum.each(1..3, fn _index ->
              try do
                transaction(fn -> raise RuntimeError, "boom" end)
              rescue
                _error in RuntimeError -> :ok
              end
            end)

            rollback(query("RELEASE SAVEPOINT hologram_3"))
          end)
        end)

      assert {:ok, {:error, {:error, %Postgrex.Error{postgres: %{code: code}}}}} = result
      assert code == :invalid_savepoint_specification
    end

    test "releases a nested transaction's savepoint when it rolls back" do
      result =
        transaction(fn ->
          transaction(fn ->
            Enum.each(1..3, fn _index -> transaction(fn -> rollback(:aborted) end) end)

            rollback(query("RELEASE SAVEPOINT hologram_3"))
          end)
        end)

      assert {:ok, {:error, {:error, %Postgrex.Error{postgres: %{code: code}}}}} = result
      assert code == :invalid_savepoint_specification
    end

    test "returns a nested transaction's result to the enclosing one" do
      assert transaction(fn -> transaction(fn -> :inner end) end) == {:ok, {:ok, :inner}}
    end

    test "rollback in a nested transaction aborts it alone and the enclosing one continues" do
      result =
        transaction(fn ->
          {:ok, %Postgrex.Result{rows: [[outer_id]]}} = query(@insert_returning_id_sql)
          Process.put(:outer_id, outer_id)

          nested_result =
            transaction(fn ->
              {:ok, %Postgrex.Result{rows: [[inner_id]]}} = query(@insert_returning_id_sql)
              Process.put(:inner_id, inner_id)
              rollback(:aborted)
            end)

          assert nested_result == {:error, :aborted}

          :continued
        end)

      outer_id = Process.get(:outer_id)

      assert result == {:ok, :continued}
      assert count_by_id(outer_id) == 1
      assert count_by_id(Process.get(:inner_id)) == 0

      delete_by_id(outer_id)
    end

    test "rolls each nesting level back on its own" do
      result =
        transaction(fn ->
          {:ok, %Postgrex.Result{rows: [[outer_id]]}} = query(@insert_returning_id_sql)
          Process.put(:outer_id, outer_id)

          transaction(fn ->
            {:ok, %Postgrex.Result{rows: [[middle_id]]}} = query(@insert_returning_id_sql)

            transaction(fn ->
              {:ok, %Postgrex.Result{rows: [[inner_id]]}} = query(@insert_returning_id_sql)
              Process.put(:inner_id, inner_id)
              rollback(:innermost)
            end)

            assert count_by_id(Process.get(:inner_id)) == 0
            assert count_by_id(middle_id) == 1

            Process.put(:middle_id, middle_id)
            rollback(:middle)
          end)

          assert count_by_id(Process.get(:middle_id)) == 0
          assert count_by_id(outer_id) == 1

          :continued
        end)

      outer_id = Process.get(:outer_id)

      assert result == {:ok, :continued}
      assert count_by_id(outer_id) == 1

      delete_by_id(outer_id)
    end

    test "rolls back and reraises on exceptions" do
      assert_error RuntimeError, "boom", fn ->
        transaction(fn ->
          {:ok, %Postgrex.Result{rows: [[id]]}} = query(@insert_returning_id_sql)
          Process.put(:inserted_id, id)
          raise RuntimeError, "boom"
        end)
      end

      assert count_by_id(Process.get(:inserted_id)) == 0
    end
  end

  describe "with_timeout/2" do
    test "applies the timeout to queries that name none" do
      # A short timeout rather than the infinite one the migration paths use, so the effect
      # shows in a moment instead of after the driver's fifteen second default - and on a
      # connection of its own, because the pool answers a client that outstays its timeout
      # by dropping the connection, which on the shared pool would disturb every other test.
      {:ok, connection_pid} =
        [connection_listeners: [self()]]
        |> Config.connection_opts()
        |> Postgrex.start_link()

      # The timeout counts from the moment the query asks for the connection, so a connect
      # still in progress would spend it before the query reached the server.
      assert_receive {:connected, _connection_process}, 15_000

      # The drop is logged as an error, which is alarming in a CI log that cannot tell an
      # intended timeout from a real outage - so it is captured, and checked below.
      {_disconnected, log} =
        ExUnit.CaptureLog.with_log(fn ->
          with_connection(connection_pid, fn ->
            # Far longer than the timeout, so the timeout fires long before the statement
            # could end on its own, however slow the runner.
            with_timeout(50, fn -> query("SELECT pg_sleep(10)") end)
          end)

          # The query can return before the drop is logged, when the timeout ran out before
          # it reached the socket. The driver logs the drop before it closes the connection
          # and reports the closed connection after, so waiting for that report means the
          # log is in.
          assert_receive {:disconnected, _connection_process}, 15_000
        end)

      GenServer.stop(connection_pid)

      # The log rather than the result, because the result races. On the timeout the driver
      # logs the drop, asks the server to cancel the statement, and closes the socket only
      # once the cancel has gone through - so a cancel slower than the rest of the sleep lets
      # the statement finish and return {:ok, _}. On Windows, which has no fork, the server
      # launches a whole new process for the cancel, which on a loaded runner can take more
      # than a second. Naming 50 ms, the log shows that this timeout was applied, not the
      # driver's fifteen second default.
      assert log =~ "checked out the connection for longer than 50ms"
    end

    test "leaves a query carrying its own timeout alone" do
      assert {:ok, %Postgrex.Result{}} =
               with_timeout(50, fn -> query("SELECT pg_sleep(1)", [], timeout: 5_000) end)
    end

    test "restores the enclosing default afterwards" do
      with_timeout(50, fn -> :ok end)

      assert {:ok, %Postgrex.Result{}} = query("SELECT pg_sleep(1)")
    end
  end

  describe "with_connection/2" do
    test "restores the enclosing connection when nested" do
      maintenance_opts = Config.connection_opts(database: "postgres")

      {:ok, outer_pid} = Postgrex.start_link(maintenance_opts)
      {:ok, inner_pid} = Postgrex.start_link(Config.connection_opts())

      after_nesting =
        with_connection(outer_pid, fn ->
          with_connection(inner_pid, fn -> :inner end)

          {:ok, %Postgrex.Result{rows: [[database]]}} = query("SELECT current_database()")

          database
        end)

      GenServer.stop(outer_pid)
      GenServer.stop(inner_pid)

      assert after_nesting == "postgres"
    end

    test "routes queries to the given connection and restores the pool afterwards" do
      database_opts =
        :hologram
        |> Application.get_env(:database, [])
        |> Config.resolve!(:test)

      {:ok, maintenance_pid} =
        Postgrex.start_link(
          database: "postgres",
          hostname: database_opts[:host],
          password: database_opts[:password],
          port: database_opts[:port],
          username: database_opts[:user]
        )

      current_database_sql = "SELECT current_database()"

      inside_result =
        with_connection(maintenance_pid, fn ->
          {:ok, %Postgrex.Result{rows: [[database]]}} = query(current_database_sql)
          database
        end)

      GenServer.stop(maintenance_pid)

      {:ok, %Postgrex.Result{rows: [[outside_database]]}} = query(current_database_sql)

      assert inside_result == "postgres"
      assert outside_database == database_opts[:database]
    end
  end
end
