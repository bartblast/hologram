defmodule Hologram.Test.DatabaseBootstrap.ConnectionTest do
  use Hologram.Test.BasicCase, async: true

  import ExUnit.CaptureLog
  import Hologram.Test.DatabaseBootstrap.Connection

  alias Hologram.DB.Config

  # What a run selects the database tests by: they are the ones that need a server.
  @moduletag :database

  defp closed_port do
    {:ok, listen_socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(listen_socket)
    :ok = :gen_tcp.close(listen_socket)

    port
  end

  defp maintenance_opts do
    Config.connection_opts(database: "postgres")
  end

  # Spawns a process that links a process accepting one connection on a fresh port and exiting
  # with the given reason once it has accepted it, then opens a connection to that port. The
  # accepted socket closes with the exit, so the connect fails right after. Returns the
  # spawned process's exit reason and its {:EXIT, ...} messages left after start/1.
  defp start_while_linked_process_exits(exit_reason) do
    {:ok, listen_socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(listen_socket)
    test_pid = self()

    {caller_pid, monitor_ref} =
      spawn_monitor(fn ->
        spawn_link(fn ->
          {:ok, _socket} = :gen_tcp.accept(listen_socket)
          exit(exit_reason)
        end)

        {:error, _reason} =
          maintenance_opts()
          |> Keyword.put(:port, port)
          |> start()

        exit_messages =
          receive do
            {:EXIT, _pid, _reason} = message -> [message]
          after
            0 -> []
          end

        send(test_pid, {:exit_messages, exit_messages})
      end)

    receive do
      {:DOWN, ^monitor_ref, :process, ^caller_pid, reason} ->
        exit_messages =
          receive do
            {:exit_messages, messages} -> messages
          after
            0 -> nil
          end

        {reason, exit_messages}
    end
  end

  describe "query!/2" do
    test "returns the result with every value as text" do
      {:ok, pid} = start(maintenance_opts())

      assert %Postgrex.Result{rows: [["1", nil]]} = query!(pid, "SELECT 1, NULL")

      stop(pid)
    end

    test "raises the error the server returns" do
      {:ok, pid} = start(maintenance_opts())

      assert_raise Postgrex.Error, ~r/relation "missing_table" does not exist/, fn ->
        query!(pid, "SELECT * FROM missing_table")
      end

      stop(pid)
    end
  end

  describe "start/1" do
    test "returns an open connection" do
      assert {:ok, pid} = start(maintenance_opts())
      assert Process.alive?(pid)

      stop(pid)
    end

    test "leaves the caller running and its mailbox clean when another linked process exits normally during the connect" do
      capture_log(fn ->
        assert start_while_linked_process_exits(:normal) == {:normal, []}
      end)
    end

    test "takes the caller down when another linked process exits abnormally during the connect" do
      capture_log(fn ->
        assert start_while_linked_process_exits(:linked_process_failed) ==
                 {:linked_process_failed, nil}
      end)
    end

    test "returns the error of a refused connection and leaves the caller running" do
      port = closed_port()

      log =
        capture_log(fn ->
          assert {:error, %DBConnection.ConnectionError{message: message}} =
                   maintenance_opts()
                   |> Keyword.put(:port, port)
                   |> start()

          assert message ==
                   "tcp connect (#{maintenance_opts()[:hostname]}:#{port}): connection refused - :econnrefused"
        end)

      assert log =~ "failed to connect to Postgres"

      refute_received {:EXIT, _pid, _reason}
    end
  end
end
