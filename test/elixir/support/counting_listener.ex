defmodule Hologram.Test.CountingListener do
  @moduledoc false

  # Listens on a free port and closes every connection it accepts, counting them - the peer a
  # connection going through Hologram.Test.ClosingTCP reaches, so that a test can tell how many
  # times the connection tried.

  use GenServer

  @doc """
  Returns how many connections the listener has accepted.
  """
  @spec accepted(GenServer.server()) :: non_neg_integer
  def accepted(listener), do: GenServer.call(listener, :accepted)

  @doc """
  Returns the port the listener listens on.
  """
  @spec port(GenServer.server()) :: :inet.port_number()
  def port(listener), do: GenServer.call(listener, :port)

  @doc """
  Starts a listener on a free port.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, nil)

  @impl GenServer
  def init(nil) do
    {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listen_socket)
    listener = self()

    spawn_link(fn -> accept_loop(listen_socket, listener) end)

    {:ok, %{accepted: 0, port: port}}
  end

  @impl GenServer
  def handle_call(:accepted, _from, state), do: {:reply, state.accepted, state}

  def handle_call(:port, _from, state), do: {:reply, state.port, state}

  @impl GenServer
  def handle_cast(:accepted, state), do: {:noreply, %{state | accepted: state.accepted + 1}}

  # Ends once the listen socket closes with the listener, whatever the reason it stopped for.
  defp accept_loop(listen_socket, listener) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        GenServer.cast(listener, :accepted)

        accept_loop(listen_socket, listener)

      {:error, :closed} ->
        :ok
    end
  end
end
