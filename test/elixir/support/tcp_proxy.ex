defmodule Hologram.Test.TCPProxy do
  @moduledoc false

  # Stands between a connection and the configured database, so that a test can decide what the
  # link does: a proxy refuses connections until open/1 makes the database reachable through it,
  # close_all/1 drops every session it carries, and freeze/1 makes them go silent - nothing is
  # forwarded either way and nothing is closed, the way a link that stopped carrying packets looks
  # to both ends.
  #
  # It holds its port from the start rather than leaving it free until it opens, since a free port
  # can be taken meanwhile by anything else binding one - another test's proxy among them.
  #
  # Refusing means accepting a connection, reading the client's startup message, then closing it.
  # The client sees a connect that failed, as it would a refused one. The whole message is read
  # first, so the close always lands at the same point of the client's connect and nothing unread
  # makes it a reset: every refused connect fails the same way, with tcp recv (idle): closed.

  use GenServer

  alias Hologram.DB.Config

  # How long a refused connection may take to send its startup message before it is closed anyway.
  @startup_timeout_ms :timer.seconds(5)

  @doc """
  Closes both ends of every connection the proxy carries, and returns :ok once they are closed.
  The proxy goes on accepting new ones.
  """
  @spec close_all(GenServer.server()) :: :ok
  def close_all(proxy), do: GenServer.call(proxy, :close_all)

  @doc """
  Stops forwarding anything on the connections the proxy carries, without closing them, and
  returns :ok.
  """
  @spec freeze(GenServer.server()) :: :ok
  def freeze(proxy), do: GenServer.call(proxy, :freeze)

  @doc """
  Forwards every connection accepted from now on to the configured database, and returns :ok.
  """
  @spec open(GenServer.server()) :: :ok
  def open(proxy), do: GenServer.call(proxy, :open)

  @doc """
  Returns the port the proxy listens on.
  """
  @spec port(GenServer.server()) :: :inet.port_number()
  def port(proxy), do: GenServer.call(proxy, :port)

  @doc """
  Starts a proxy listening on a free port, refusing connections until open/1.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, nil)

  @impl GenServer
  def init(nil) do
    {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listen_socket)
    proxy = self()

    spawn_link(fn -> accept_loop(listen_socket, proxy) end)

    {:ok, %{carriers: [], listen_socket: listen_socket, open?: false, port: port}}
  end

  @impl GenServer
  def handle_call(:close_all, _from, state) do
    for carrier <- state.carriers do
      ref = Process.monitor(carrier)
      send(carrier, :close)

      receive do
        {:DOWN, ^ref, :process, ^carrier, _reason} -> :ok
      end
    end

    {:reply, :ok, %{state | carriers: []}}
  end

  def handle_call(:freeze, _from, state) do
    Enum.each(state.carriers, &send(&1, :freeze))

    {:reply, :ok, state}
  end

  def handle_call(:new_carrier, _from, %{open?: false} = state) do
    refuser =
      spawn_link(fn ->
        receive do
          {:client, client} -> refuse(client)
        end
      end)

    {:reply, refuser, state}
  end

  def handle_call(:new_carrier, _from, state) do
    carrier =
      spawn_link(fn ->
        receive do
          {:client, client} -> carry(client)
        end
      end)

    {:reply, carrier, %{state | carriers: [carrier | state.carriers]}}
  end

  def handle_call(:open, _from, state) do
    {:reply, :ok, %{state | open?: true}}
  end

  def handle_call(:port, _from, state) do
    {:reply, state.port, state}
  end

  defp accept_loop(listen_socket, proxy) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client} ->
        carrier = GenServer.call(proxy, :new_carrier)
        :ok = :gen_tcp.controlling_process(client, carrier)
        send(carrier, {:client, client})

        accept_loop(listen_socket, proxy)

      {:error, :closed} ->
        :ok
    end
  end

  defp carry(client) do
    opts = Config.connection_opts()
    host = String.to_charlist(opts[:hostname])

    {:ok, upstream} = :gen_tcp.connect(host, opts[:port], [:binary, active: true])

    :ok = :inet.setopts(client, active: true)

    forward(client, upstream, false)
  end

  defp close(client, upstream) do
    :gen_tcp.close(client)
    :gen_tcp.close(upstream)
  end

  defp forward(client, upstream, frozen?) do
    receive do
      {:tcp, ^client, data} ->
        unless frozen?, do: :gen_tcp.send(upstream, data)
        forward(client, upstream, frozen?)

      {:tcp, ^upstream, data} ->
        unless frozen?, do: :gen_tcp.send(client, data)
        forward(client, upstream, frozen?)

      :freeze ->
        forward(client, upstream, true)

      :close ->
        close(client, upstream)

      {:tcp_closed, _socket} ->
        close(client, upstream)

      {:tcp_error, _socket, _reason} ->
        close(client, upstream)
    end
  end

  # The startup message opens with its length, which counts itself.
  defp refuse(client) do
    with {:ok, <<length::32>>} <- :gen_tcp.recv(client, 4, @startup_timeout_ms) do
      :gen_tcp.recv(client, length - 4, @startup_timeout_ms)
    end

    :gen_tcp.close(client)
  end
end
