defmodule Hologram.Test.DatabaseBootstrap.Connection do
  @moduledoc false

  # A single Postgres connection that opens synchronously, for the test database bootstrap.
  # A pooled connection opens in the background, and a query queued on it gives up after the
  # pool's queue window, so a server slow to answer its first connection looks like no server
  # at all. Here start/1 returns once the connection is open, or returns the driver's error.

  @behaviour Postgrex.SimpleConnection

  alias Postgrex.SimpleConnection

  @impl SimpleConnection
  def handle_call({:query, statement}, from, state) do
    {:query, statement, %{state | from: from}}
  end

  @impl SimpleConnection
  def handle_result(results_or_error, state) do
    SimpleConnection.reply(state.from, results_or_error)

    {:noreply, %{state | from: nil}}
  end

  @impl SimpleConnection
  def init(_args), do: {:ok, %{from: nil}}

  @impl SimpleConnection
  def notify(_channel, _payload, _state), do: :ok

  @doc """
  Runs one SQL statement over the simple query protocol and returns its result, with every
  value as text. Raises the Postgrex.Error the server returns.

  Waits as long as the server takes: the connection is open, so the server either answers or
  the connection breaks, which stops the connection process and exits the caller.
  """
  @spec query!(pid, String.t()) :: Postgrex.Result.t()
  def query!(pid, statement) do
    case SimpleConnection.call(pid, {:query, statement}, :infinity) do
      [result] -> result
      %Postgrex.Error{} = error -> raise error
    end
  end

  @doc """
  Opens a connection with the given Postgrex connection options and returns {:ok, pid}, or
  {:error, exception} when the server refuses it or cannot be reached.

  The connection is linked to the caller.
  """
  @spec start(keyword) :: {:ok, pid} | {:error, Exception.t()}
  def start(opts) do
    # A failed connect makes the connection exit with the error, and the link would take the
    # caller down with it. The start unlinks the dead connection and flushes its exit message
    # itself, so no message of the connection's is left behind.
    trap_exit? = Process.flag(:trap_exit, true)

    try do
      SimpleConnection.start_link(__MODULE__, nil, opts)
    after
      Process.flag(:trap_exit, trap_exit?)

      unless trap_exit? do
        exit_on_trapped_exit_signal()
      end
    end
  end

  @doc """
  Closes the connection.
  """
  @spec stop(pid) :: :ok
  def stop(pid), do: :gen_statem.stop(pid)

  # The connect can wait on a slow server for as long as it takes, and an exit signal another
  # linked process sent meanwhile arrived as a message. A caller that doesn't trap exits would
  # have been taken down by any but a normal one, so it is taken down now, with the first
  # one's reason - an open connection goes down with it through the link.
  defp exit_on_trapped_exit_signal do
    receive do
      {:EXIT, _pid, :normal} -> exit_on_trapped_exit_signal()
      {:EXIT, _pid, reason} -> exit(reason)
    after
      0 -> :ok
    end
  end
end
